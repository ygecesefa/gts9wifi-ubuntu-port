// gts9w-tool: the few things the recovery installer needs and a stock
// recovery ramdisk (LineageOS or TWRP) cannot be relied on to have.
//
//   gts9w-tool keys SECONDS          wait for Volume Up (exit 0) or Volume
//                                    Down (exit 1); 2 on timeout or error
//   gts9w-tool presses SECONDS       count volume-key presses, either key:
//                                    two or more (exit 0), one (exit 1), none
//                                    in SECONDS or error (2).  In Android,
//                                    which physical key sends Volume Up
//                                    depends on the screen rotation.
//   gts9w-tool extract ZIP NAME OUT  copy one stored (uncompressed) entry
//   gts9w-tool unzstd IN OUT         decompress a .zst file to a file or a
//                                    block device, printing progress
//   gts9w-tool zip [-0] OUT NAME=FILE...
//                                    write a zip, entries deflated (-0: stored,
//                                    so `extract` can read them back)
//
// Built static (glibc + libz.a + libzstd.a) by
// scripts/build-gts9wifi-installer-zip.sh, so it runs from /tmp in any
// arm64 recovery.  No zip64: every entry and the archive stay below 4 GiB.
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#include <zlib.h>
#include <zstd.h>

#define BUF (4 << 20)

static int die(const char *what)
{
	fprintf(stderr, "gts9w-tool: %s: %s\n", what, strerror(errno));
	return 2;
}

/* ---- keys ------------------------------------------------------------ */

static long now_ms(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * 1000L + ts.tv_nsec / 1000000;
}

/* keys: the first Volume Up / Down release decides.  presses: any volume
 * key; after the first release, more releases within 1.5 s each are
 * counted. */
static int cmd_keys(int seconds, int count)
{
	struct pollfd fds[32];
	int n = 0, presses = 0;
	DIR *dir = opendir("/dev/input");
	struct dirent *de;

	if (!dir)
		return die("/dev/input");
	while ((de = readdir(dir)) && n < 32) {
		char path[300];

		if (strncmp(de->d_name, "event", 5))
			continue;
		snprintf(path, sizeof(path), "/dev/input/%s", de->d_name);
		fds[n].fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
		if (fds[n].fd >= 0)
			fds[n++].events = POLLIN;
	}
	closedir(dir);
	if (!n)
		return die("no input devices");

	/* Drop whatever was queued before the question was shown. */
	for (int i = 0; i < n; i++) {
		struct input_event ev;

		while (read(fds[i].fd, &ev, sizeof(ev)) == sizeof(ev))
			;
	}

	long end = now_ms() + seconds * 1000L;
	for (;;) {
		long left = end - now_ms();

		if (left <= 0)
			return presses >= 2 ? 0 : presses == 1 ? 1 : 2;
		if (poll(fds, n, (int)left) <= 0)
			continue;
		for (int i = 0; i < n; i++) {
			struct input_event ev;

			if (!(fds[i].revents & POLLIN))
				continue;
			while (read(fds[i].fd, &ev, sizeof(ev)) == sizeof(ev)) {
				/* Act on the release, so the key is not still down
				 * when the next question starts listening. */
				if (ev.type != EV_KEY || ev.value != 0)
					continue;
				if (ev.code != KEY_VOLUMEUP && ev.code != KEY_VOLUMEDOWN)
					continue;
				if (!count)
					return ev.code == KEY_VOLUMEUP ? 0 : 1;
				presses++;
				end = now_ms() + 1500;
			}
		}
	}
}

/* ---- zip reading (stored entries only) -------------------------------- */

static uint16_t le16(const unsigned char *p) { return p[0] | p[1] << 8; }
static uint32_t le32(const unsigned char *p)
{
	return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24;
}

static int copy_range(int in, off_t off, uint64_t len, int out)
{
	static unsigned char buf[BUF];

	if (lseek(in, off, SEEK_SET) < 0)
		return die("seek");
	while (len) {
		size_t want = len > BUF ? BUF : len;
		ssize_t got = read(in, buf, want);

		if (got <= 0)
			return die("read");
		for (ssize_t done = 0; done < got;) {
			ssize_t w = write(out, buf + done, got - done);

			if (w <= 0)
				return die("write");
			done += w;
		}
		len -= got;
	}
	return 0;
}

static int cmd_extract(const char *zip, const char *name, const char *outpath)
{
	int fd = open(zip, O_RDONLY | O_CLOEXEC);
	struct stat st;
	unsigned char tail[65557], *eocd = NULL;

	if (fd < 0 || fstat(fd, &st))
		return die(zip);
	off_t tlen = st.st_size < (off_t)sizeof(tail) ? st.st_size : (off_t)sizeof(tail);
	if (pread(fd, tail, tlen, st.st_size - tlen) != tlen)
		return die("read end of zip");
	for (off_t i = tlen - 22; i >= 0; i--)
		if (le32(tail + i) == 0x06054b50) {
			eocd = tail + i;
			break;
		}
	if (!eocd) {
		fprintf(stderr, "gts9w-tool: %s: not a zip\n", zip);
		return 2;
	}

	uint32_t cd_size = le32(eocd + 12), cd_off = le32(eocd + 16);
	unsigned char *cd = malloc(cd_size);
	if (!cd || pread(fd, cd, cd_size, cd_off) != (ssize_t)cd_size)
		return die("read central directory");

	size_t namelen = strlen(name);
	for (uint32_t p = 0; p + 46 <= cd_size;) {
		unsigned char *e = cd + p;
		uint16_t nl = le16(e + 28), xl = le16(e + 30), cl = le16(e + 32);

		if (le32(e) != 0x02014b50)
			break;
		if (nl == namelen && !memcmp(e + 46, name, nl)) {
			unsigned char lh[30];
			uint32_t lho = le32(e + 42), size = le32(e + 20);

			if (le16(e + 10) != 0) {
				fprintf(stderr, "gts9w-tool: %s is compressed; store it\n", name);
				return 2;
			}
			if (pread(fd, lh, 30, lho) != 30 || le32(lh) != 0x04034b50)
				return die("local header");
			int out = open(outpath, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
			if (out < 0)
				return die(outpath);
			int r = copy_range(fd, lho + 30 + le16(lh + 26) + le16(lh + 28), size, out);
			if (!r && fsync(out))
				r = die("fsync");
			close(out);
			return r;
		}
		p += 46 + nl + xl + cl;
	}
	fprintf(stderr, "gts9w-tool: %s not in %s\n", name, zip);
	return 2;
}

/* ---- unzstd ----------------------------------------------------------- */

static int cmd_unzstd(const char *inpath, const char *outpath)
{
	int in = open(inpath, O_RDONLY | O_CLOEXEC);
	int out = open(outpath, O_WRONLY | O_CLOEXEC);
	struct stat st;
	static unsigned char ibuf[BUF], obuf[BUF];
	ZSTD_DStream *z = ZSTD_createDStream();
	uint64_t total, done = 0;
	int last = -1;

	if (out < 0)
		out = open(outpath, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
	if (in < 0 || out < 0 || fstat(in, &st) || !z)
		return die("unzstd open");
	total = st.st_size;
	ZSTD_initDStream(z);

	for (;;) {
		ssize_t got = read(in, ibuf, BUF);

		if (got < 0)
			return die("read");
		if (!got)
			break;
		ZSTD_inBuffer ib = { ibuf, (size_t)got, 0 };
		while (ib.pos < ib.size) {
			ZSTD_outBuffer ob = { obuf, BUF, 0 };
			size_t r = ZSTD_decompressStream(z, &ob, &ib);

			if (ZSTD_isError(r)) {
				fprintf(stderr, "gts9w-tool: zstd: %s\n", ZSTD_getErrorName(r));
				return 2;
			}
			for (size_t w = 0; w < ob.pos;) {
				ssize_t k = write(out, obuf + w, ob.pos - w);

				if (k <= 0)
					return die("write");
				w += k;
			}
		}
		done += got;
		int pct = (int)(done * 100 / total);
		if (pct / 5 != last / 5) {
			/* Writes land in the page cache first (12 GB of RAM): flush
			 * before each step so the percentage is what is on the card. */
			if (fdatasync(out))
				return die("fdatasync");
			printf("%d\n", pct);
			fflush(stdout);
			last = pct;
		}
	}
	if (fsync(out))
		return die("fsync");
	close(out);
	return 0;
}

/* ---- zip writing ------------------------------------------------------ */

struct entry {
	const char *name;
	uint32_t crc, csize, usize, offset;
};

static void put16(FILE *f, uint16_t v) { fputc(v & 255, f); fputc(v >> 8, f); }
static void put32(FILE *f, uint32_t v) { put16(f, v & 0xffff); put16(f, v >> 16); }

static int method = 8;	/* 8 deflate, 0 store */

static void local_header(FILE *f, const struct entry *e)
{
	put32(f, 0x04034b50); put16(f, 20); put16(f, 0); put16(f, method);
	put16(f, 0); put16(f, 0x21);            /* 1980-01-01 00:00 */
	put32(f, e->crc); put32(f, e->csize); put32(f, e->usize);
	put16(f, strlen(e->name)); put16(f, 0);
	fwrite(e->name, 1, strlen(e->name), f);
}

static int cmd_zip(const char *outpath, int argc, char **argv)
{
	FILE *f = fopen(outpath, "wb");
	struct entry *ents = calloc(argc, sizeof(*ents));
	static unsigned char ibuf[BUF], obuf[BUF];

	if (!f || !ents)
		return die(outpath);
	for (int i = 0; i < argc; i++) {
		char *eq = strchr(argv[i], '=');
		struct entry *e = &ents[i];

		if (!eq) {
			fprintf(stderr, "gts9w-tool: want NAME=FILE, got %s\n", argv[i]);
			return 2;
		}
		*eq = 0;
		e->name = argv[i];
		FILE *in = fopen(eq + 1, "rb");
		if (!in)
			return die(eq + 1);

		/* Placeholder header; rewritten once sizes and CRC are known. */
		e->offset = ftell(f);
		local_header(f, e);

		z_stream zs = { 0 };
		deflateInit2(&zs, 6, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY);
		uLong crc = crc32(0, NULL, 0);
		uint64_t usize = 0, csize = 0;
		int flush;
		do {
			size_t got = fread(ibuf, 1, BUF, in);

			if (ferror(in))
				return die("read");
			flush = feof(in) ? Z_FINISH : Z_NO_FLUSH;
			crc = crc32(crc, ibuf, got);
			usize += got;
			if (!method) {
				if (fwrite(ibuf, 1, got, f) != got)
					return die("write");
				csize += got;
				continue;
			}
			zs.next_in = ibuf;
			zs.avail_in = got;
			do {
				zs.next_out = obuf;
				zs.avail_out = BUF;
				deflate(&zs, flush);
				size_t have = BUF - zs.avail_out;
				if (fwrite(obuf, 1, have, f) != have)
					return die("write");
				csize += have;
			} while (zs.avail_out == 0);
		} while (flush != Z_FINISH);
		deflateEnd(&zs);
		fclose(in);
		if (usize >= 0xffffffffu || csize >= 0xffffffffu) {
			fprintf(stderr, "gts9w-tool: %s is too large for a zip without zip64\n", e->name);
			return 2;
		}
		e->crc = crc;
		e->usize = usize;
		e->csize = csize;
		long end = ftell(f);
		fseek(f, e->offset, SEEK_SET);
		local_header(f, e);
		fseek(f, end, SEEK_SET);
	}

	long cd = ftell(f);
	for (int i = 0; i < argc; i++) {
		struct entry *e = &ents[i];

		put32(f, 0x02014b50); put16(f, 0x031e); put16(f, 20); put16(f, 0);
		put16(f, method); put16(f, 0); put16(f, 0x21);
		put32(f, e->crc); put32(f, e->csize); put32(f, e->usize);
		put16(f, strlen(e->name)); put16(f, 0); put16(f, 0);
		put16(f, 0); put16(f, 0); put32(f, 0100644u << 16);
		put32(f, e->offset);
		fwrite(e->name, 1, strlen(e->name), f);
	}
	long cdlen = ftell(f) - cd;
	put32(f, 0x06054b50); put16(f, 0); put16(f, 0);
	put16(f, argc); put16(f, argc); put32(f, cdlen); put32(f, cd); put16(f, 0);
	if (fflush(f) || fsync(fileno(f)) || fclose(f))
		return die("close zip");
	return 0;
}

int main(int argc, char **argv)
{
	if (argc >= 3 && !strcmp(argv[1], "keys"))
		return cmd_keys(atoi(argv[2]), 0);
	if (argc >= 3 && !strcmp(argv[1], "presses"))
		return cmd_keys(atoi(argv[2]), 1);
	if (argc == 5 && !strcmp(argv[1], "extract"))
		return cmd_extract(argv[2], argv[3], argv[4]);
	if (argc == 4 && !strcmp(argv[1], "unzstd"))
		return cmd_unzstd(argv[2], argv[3]);
	if (argc >= 5 && !strcmp(argv[1], "zip") && !strcmp(argv[2], "-0")) {
		method = 0;
		return cmd_zip(argv[3], argc - 4, argv + 4);
	}
	if (argc >= 4 && !strcmp(argv[1], "zip"))
		return cmd_zip(argv[2], argc - 3, argv + 3);
	fprintf(stderr, "usage: gts9w-tool keys|presses SECONDS | extract ZIP NAME OUT | "
		"unzstd IN OUT | zip [-0] OUT NAME=FILE...\n");
	return 2;
}
