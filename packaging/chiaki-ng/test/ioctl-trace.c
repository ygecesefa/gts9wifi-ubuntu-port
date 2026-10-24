/* LD_PRELOAD: log V4L2 ioctls (format, buffers, stream on/off, events and
 * every failure) and dump the first output-queue (bitstream) buffers, to
 * see what chiaki-ng's FFmpeg sends to the iris decoder.
 * Log: $V4L2_TRACE (default /tmp/v4l2-trace.log); dump: $V4L2_DUMP. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <linux/videodev2.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>

static FILE *logf_;
static int qbufs, dqbufs;

static void tlog(const char *fmt, ...)
{
	if(!logf_)
	{
		const char *p = getenv("V4L2_TRACE");
		logf_ = fopen(p && *p ? p : "/tmp/v4l2-trace.log", "a");
		if(!logf_)
			return;
		setvbuf(logf_, NULL, _IOLBF, 0);
	}
	va_list ap;
	va_start(ap, fmt);
	vfprintf(logf_, fmt, ap);
	va_end(ap);
}

static const char *name(unsigned long req)
{
	switch(req)
	{
		case VIDIOC_QUERYCAP: return "QUERYCAP";
		case VIDIOC_S_FMT: return "S_FMT";
		case VIDIOC_G_FMT: return "G_FMT";
		case VIDIOC_TRY_FMT: return "TRY_FMT";
		case VIDIOC_REQBUFS: return "REQBUFS";
		case VIDIOC_QUERYBUF: return "QUERYBUF";
		case VIDIOC_QBUF: return "QBUF";
		case VIDIOC_DQBUF: return "DQBUF";
		case VIDIOC_STREAMON: return "STREAMON";
		case VIDIOC_STREAMOFF: return "STREAMOFF";
		case VIDIOC_DQEVENT: return "DQEVENT";
		case VIDIOC_SUBSCRIBE_EVENT: return "SUBSCRIBE_EVENT";
		case VIDIOC_G_SELECTION: return "G_SELECTION";
		case VIDIOC_S_SELECTION: return "S_SELECTION";
		case VIDIOC_DECODER_CMD: return "DECODER_CMD";
		case VIDIOC_TRY_DECODER_CMD: return "TRY_DECODER_CMD";
		case VIDIOC_G_CTRL: return "G_CTRL";
		case VIDIOC_S_CTRL: return "S_CTRL";
		case VIDIOC_ENUM_FMT: return "ENUM_FMT";
		case VIDIOC_EXPBUF: return "EXPBUF";
		default: return NULL;
	}
}

int ioctl(int fd, unsigned long req, ...)
{
	static int (*real)(int, unsigned long, ...);
	if(!real)
		real = dlsym(RTLD_NEXT, "ioctl");
	va_list ap;
	va_start(ap, req);
	void *arg = va_arg(ap, void *);
	va_end(ap);
	const char *n = name(req);
	if(!n)
		return real(fd, req, arg);
	int r = real(fd, req, arg);
	int e = errno;
	if(req == VIDIOC_S_FMT || req == VIDIOC_G_FMT)
	{
		struct v4l2_format *f = arg;
		tlog("%s type %u %ux%u fourcc %.4s planes %u size0 %u -> %d %s\n", n, f->type, f->fmt.pix_mp.width,
			f->fmt.pix_mp.height, (char *)&f->fmt.pix_mp.pixelformat, f->fmt.pix_mp.num_planes,
			f->fmt.pix_mp.plane_fmt[0].sizeimage, r, r ? strerror(e) : "");
	}
	else if(req == VIDIOC_REQBUFS)
	{
		struct v4l2_requestbuffers *b = arg;
		tlog("REQBUFS type %u count %u -> %d %s\n", b->type, b->count, r, r ? strerror(e) : "");
	}
	else if(req == VIDIOC_QBUF || req == VIDIOC_DQBUF)
	{
		struct v4l2_buffer *b = arg;
		unsigned used = b->m.planes ? b->m.planes[0].bytesused : 0;
		int *cnt = req == VIDIOC_QBUF ? &qbufs : &dqbufs;
		if(r || (*cnt)++ < 40)
			tlog("%s type %u idx %u used %u flags %#x -> %d %s\n", n, b->type, b->index, used, b->flags, r, r ? strerror(e) : "");
	}
	else if(req == VIDIOC_DQEVENT)
	{
		struct v4l2_event *ev = arg;
		if(!r)
			tlog("DQEVENT type %u changes %#x\n", ev->type, ev->u.src_change.changes);
	}
	else if(r && e != EAGAIN)
		tlog("%s -> %d %s\n", n, r, strerror(e));
	else if(req == VIDIOC_STREAMON || req == VIDIOC_STREAMOFF || req == VIDIOC_DECODER_CMD)
		tlog("%s type %u -> %d\n", n, req == VIDIOC_DECODER_CMD ? 0 : *(unsigned *)arg, r);
	errno = e;
	return r;
}
