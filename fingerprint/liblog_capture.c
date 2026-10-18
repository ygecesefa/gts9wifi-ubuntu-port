// SPDX-License-Identifier: MIT
//
// LD_PRELOAD shim for Samsung's sec_nvm/spdaemon running on Ubuntu.
//
// Android's liblog sends everything to logd over /dev/socket/logdw, which
// does not exist here, so the daemons' messages vanish -- including the
// "SP Apps were loaded successfully" line the secure-start supervisor waits
// for.  Interpose the liblog entry points and write "P/tag: message" lines to
// stderr instead, which the supervisor captures into a log file.
//
// Built against the tablet's own bionic libc (build-liblog-capture.sh); it
// uses nothing but snprintf, vsnprintf and write, and needs no NDK sysroot.
#include <stdarg.h>
#include <stddef.h>

/* bionic's own prototypes; declared here so no NDK sysroot is needed */
typedef long ssize_t;
int snprintf(char *str, size_t size, const char *fmt, ...);
int vsnprintf(char *str, size_t size, const char *fmt, va_list ap);
ssize_t write(int fd, const void *buf, size_t count);

#define EXPORT __attribute__((visibility("default")))

static const char prio_char[] = "??VDIWEFS";

static int emit(int prio, const char *tag, const char *text)
{
	char line[1024];
	int n = snprintf(line, sizeof(line), "%c/%s: %s\n",
			 prio >= 0 && prio < (int)sizeof(prio_char) - 1 ?
			 prio_char[prio] : '?', tag ? tag : "", text ? text : "");
	if (n < 0)
		return n;
	if (n >= (int)sizeof(line))
		n = sizeof(line) - 1;
	return (int)write(2, line, n);
}

EXPORT int __android_log_write(int prio, const char *tag, const char *text)
{
	return emit(prio, tag, text);
}

EXPORT int __android_log_buf_write(int bufid, int prio, const char *tag,
				   const char *text)
{
	(void)bufid;
	return emit(prio, tag, text);
}

EXPORT int __android_log_vprint(int prio, const char *tag, const char *fmt,
				va_list ap)
{
	char text[1000];

	vsnprintf(text, sizeof(text), fmt, ap);
	return emit(prio, tag, text);
}

EXPORT int __android_log_print(int prio, const char *tag, const char *fmt, ...)
{
	va_list ap;
	int ret;

	va_start(ap, fmt);
	ret = __android_log_vprint(prio, tag, fmt, ap);
	va_end(ap);
	return ret;
}

EXPORT int __android_log_buf_print(int bufid, int prio, const char *tag,
				   const char *fmt, ...)
{
	va_list ap;
	int ret;

	(void)bufid;
	va_start(ap, fmt);
	ret = __android_log_vprint(prio, tag, fmt, ap);
	va_end(ap);
	return ret;
}

/* liblog's structured entry point, used by libbase LOG() and LOG(FATAL). */
struct __android_log_message {
	size_t struct_size;
	int buffer_id;
	int priority;
	const char *tag;
	const char *file;
	unsigned int line;
	const char *message;
};

EXPORT void __android_log_write_log_message(struct __android_log_message *msg)
{
	if (msg)
		emit(msg->priority, msg->tag, msg->message);
}

void abort(void);

EXPORT void __android_log_assert(const char *cond, const char *tag,
				 const char *fmt, ...)
{
	char text[1000];
	va_list ap;

	if (fmt) {
		va_start(ap, fmt);
		vsnprintf(text, sizeof(text), fmt, ap);
		va_end(ap);
		emit(7, tag, text);
	} else {
		emit(7, tag, cond ? cond : "assertion failed");
	}
	abort();
}

/* Never drop a message because of a priority filter. */
EXPORT int __android_log_is_loggable(int prio, const char *tag, int def)
{
	(void)prio; (void)tag; (void)def;
	return 1;
}

EXPORT int __android_log_is_loggable_len(int prio, const char *tag, size_t len,
					 int def)
{
	(void)prio; (void)tag; (void)len; (void)def;
	return 1;
}
