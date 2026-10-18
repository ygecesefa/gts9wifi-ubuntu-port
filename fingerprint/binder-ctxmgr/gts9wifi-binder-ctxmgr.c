// SPDX-License-Identifier: MIT
//
// A minimal binder context manager ("service manager") with no services.
//
// The X710's Samsung spdaemon links libbinder (through libhardware_legacy's
// wakelock calls) and will not start the SPU until something owns handle 0
// on /dev/vndbinder: it loops on "Waiting 1s on context object".  Android's
// vndservicemanager cannot run here, it aborts without SELinux.  This
// answers PING_TRANSACTION so the context object exists and replies to every
// other transaction with an error, so service lookups simply fail (the
// wakelock is not needed on Ubuntu).
//
//   gts9wifi-binder-ctxmgr /dev/vndbinder
#include <errno.h>
#include <fcntl.h>
#include <linux/android/binder.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

#define PING_TRANSACTION	0x5f504e47	/* B_PACK_CHARS('_','P','N','G') */
#define MAP_SIZE		(128 * 1024)

static int fd;

static int write_cmds(const void *buf, size_t len)
{
	struct binder_write_read bwr = {
		.write_size = len,
		.write_buffer = (uintptr_t)buf,
	};

	return ioctl(fd, BINDER_WRITE_READ, &bwr);
}

/* Free the incoming buffer and reply: empty for a ping, an error otherwise. */
static void reply(const struct binder_transaction_data *txn)
{
	struct {
		uint32_t free_cmd;
		binder_uintptr_t buffer;
		uint32_t reply_cmd;
		struct binder_transaction_data data;
	} __attribute__((packed)) out = { 0 };
	static int32_t status = -EPERM;		/* -> PERMISSION_DENIED */

	out.free_cmd = BC_FREE_BUFFER;
	out.buffer = txn->data.ptr.buffer;
	if (txn->flags & TF_ONE_WAY) {
		write_cmds(&out, sizeof(out.free_cmd) + sizeof(out.buffer));
		return;
	}
	out.reply_cmd = BC_REPLY;
	if (txn->code != PING_TRANSACTION) {
		out.data.flags = TF_STATUS_CODE;
		out.data.data_size = sizeof(status);
		out.data.data.ptr.buffer = (uintptr_t)&status;
	}
	write_cmds(&out, sizeof(out));
}

int main(int argc, char **argv)
{
	const char *dev = argc > 1 ? argv[1] : "/dev/vndbinder";
	uint32_t readbuf[128];

	fd = open(dev, O_RDWR | O_CLOEXEC);
	if (fd < 0 || mmap(NULL, MAP_SIZE, PROT_READ, MAP_PRIVATE, fd, 0) == MAP_FAILED) {
		perror(dev);
		return 1;
	}
	if (ioctl(fd, BINDER_SET_CONTEXT_MGR, 0)) {
		perror("BINDER_SET_CONTEXT_MGR");
		return 1;
	}
	uint32_t enter = BC_ENTER_LOOPER;
	write_cmds(&enter, sizeof(enter));
	fprintf(stderr, "context manager on %s\n", dev);

	for (;;) {
		struct binder_write_read bwr = {
			.read_size = sizeof(readbuf),
			.read_buffer = (uintptr_t)readbuf,
		};
		if (ioctl(fd, BINDER_WRITE_READ, &bwr)) {
			if (errno == EINTR)
				continue;
			perror("BINDER_WRITE_READ");
			return 1;
		}
		uint8_t *p = (uint8_t *)readbuf, *end = p + bwr.read_consumed;
		while (p + sizeof(uint32_t) <= end) {
			uint32_t cmd = *(uint32_t *)p;
			p += sizeof(uint32_t);
			switch (cmd) {
			case BR_NOOP:
			case BR_TRANSACTION_COMPLETE:
			case BR_SPAWN_LOOPER:
				break;
			case BR_INCREFS:
			case BR_ACQUIRE: {
				/* Acknowledge with the matching *_DONE command. */
				struct {
					uint32_t cmd;
					struct binder_ptr_cookie pc;
				} __attribute__((packed)) ack;
				ack.cmd = cmd == BR_INCREFS ? BC_INCREFS_DONE : BC_ACQUIRE_DONE;
				memcpy(&ack.pc, p, sizeof(ack.pc));
				write_cmds(&ack, sizeof(ack));
				p += sizeof(struct binder_ptr_cookie);
				break;
			}
			case BR_RELEASE:
			case BR_DECREFS:
				p += sizeof(struct binder_ptr_cookie);
				break;
			case BR_TRANSACTION:
			case BR_TRANSACTION_SEC_CTX: {
				struct binder_transaction_data txn;
				if (cmd == BR_TRANSACTION_SEC_CTX) {
					memcpy(&txn, p, sizeof(txn));
					p += sizeof(struct binder_transaction_data_secctx);
				} else {
					memcpy(&txn, p, sizeof(txn));
					p += sizeof(txn);
				}
				reply(&txn);
				break;
			}
			case BR_REPLY:
				p += sizeof(struct binder_transaction_data);
				break;
			case BR_DEAD_BINDER:
			case BR_CLEAR_DEATH_NOTIFICATION_DONE:
				p += sizeof(binder_uintptr_t);
				break;
			case BR_FAILED_REPLY:
			case BR_DEAD_REPLY:
				break;
			default:
				fprintf(stderr, "unhandled binder command %#x\n", cmd);
				p = end;
				break;
			}
		}
	}
}
