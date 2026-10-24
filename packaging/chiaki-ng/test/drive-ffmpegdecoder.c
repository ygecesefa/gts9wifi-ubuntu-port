/* Drives chiaki-ng's real lib/src/ffmpegdecoder.c (patched) like the
 * stream does: SPS/PPS as a unit of its own, then one access unit per
 * call, 60 fps; counts frames and checks luma.  Stubs for the rest of
 * libchiaki.  Build next to a patched lib/src/ffmpegdecoder.c and
 * lib/include/chiaki/*.h (config.h: #define CHIAKI_EXPORT), against the
 * Flatpak's FFmpeg 7.1:
 *   gcc -std=gnu11 -I. -o drive drive-ffmpegdecoder.c ffmpegdecoder.c \
 *     $(pkg-config --static --cflags --libs libavcodec libavutil) -lpthread
 *   ./drive ps.h264 v4l2m2m */
#include <chiaki/ffmpegdecoder.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

ChiakiErrorCode chiaki_mutex_init(ChiakiMutex *m, bool rec) { return pthread_mutex_init(&m->mutex, NULL) ? CHIAKI_ERR_UNKNOWN : CHIAKI_ERR_SUCCESS; }
ChiakiErrorCode chiaki_mutex_fini(ChiakiMutex *m) { pthread_mutex_destroy(&m->mutex); return CHIAKI_ERR_SUCCESS; }
ChiakiErrorCode chiaki_mutex_lock(ChiakiMutex *m) { pthread_mutex_lock(&m->mutex); return CHIAKI_ERR_SUCCESS; }
ChiakiErrorCode chiaki_mutex_unlock(ChiakiMutex *m) { pthread_mutex_unlock(&m->mutex); return CHIAKI_ERR_SUCCESS; }
void chiaki_log(ChiakiLog *log, ChiakiLogLevel level, const char *fmt, ...)
{
	va_list ap; va_start(ap, fmt); fprintf(stderr, "[chiaki %d] ", level); vfprintf(stderr, fmt, ap); fputc('\n', stderr); va_end(ap);
}
uint64_t chiaki_time_now_monotonic_us(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1000000ull + t.tv_nsec / 1000; }
const char *chiaki_codec_name(ChiakiCodec c) { return "codec"; }

static int frames, green;
static void cb(ChiakiFfmpegDecoder *d, void *u)
{
	int32_t lost;
	ChiakiFfmpegFrame f = chiaki_ffmpeg_decoder_pull_frame(d, &lost);
	if(!f.frame)
		return;
	frames++;
	long sum = 0, n = 0;
	for(int y = 0; y < f.frame->height; y += 32)
		for(int x = 0; x < f.frame->width; x += 32, n++)
			sum += f.frame->data[0][y * f.frame->linesize[0] + x];
	if(n && sum / n < 5)
		green++;
	av_frame_free(&f.frame);
}

int main(int argc, char **argv)
{
	FILE *fp = fopen(argv[1], "rb");
	fseek(fp, 0, SEEK_END); long len = ftell(fp); fseek(fp, 0, SEEK_SET);
	uint8_t *data = malloc(len + 64); fread(data, 1, len, fp); memset(data + len, 0, 64);
	ChiakiFfmpegDecoder dec;
	ChiakiLog log = {0};
	if(chiaki_ffmpeg_decoder_init(&dec, &log, CHIAKI_CODEC_H264, 1920, 1080, 60, argc > 2 ? argv[2] : "v4l2m2m", NULL, cb, NULL))
		return 1;
	AVCodecParserContext *parser = av_parser_init(AV_CODEC_ID_H264);
	AVCodecContext *pctx = avcodec_alloc_context3(NULL);
	long off = 0; int aus = 0, failed = 0;
	while(off < len)
	{
		uint8_t *au; int au_size;
		off += av_parser_parse2(parser, pctx, &au, &au_size, data + off, len - off, AV_NOPTS_VALUE, AV_NOPTS_VALUE, 0);
		if(!au_size)
			continue;
		uint8_t *copy = malloc(au_size + 64);
		memcpy(copy, au, au_size); memset(copy + au_size, 0, 64);
		int start = 0;
		if(++aus == 1)
		{
			for(int i = 0; i + 4 < au_size; i++)
				if(!copy[i] && !copy[i + 1] && copy[i + 2] == 1 && ((copy[i + 3] & 0x1f) == 5 || (copy[i + 3] & 0x1f) == 6))
				{ start = i && !copy[i - 1] ? i - 1 : i; break; }
			if(!chiaki_ffmpeg_decoder_video_sample_cb(copy, start, 0, false, &dec))
				failed++;
		}
		if(!chiaki_ffmpeg_decoder_video_sample_cb(copy + start, au_size - start, 0, false, &dec))
			failed++;
		free(copy);
		usleep(16000);
	}
	printf("%s: AUs %d (+1 header unit), frames %d, empty (green) frames %d, failed sample_cb %d\n",
		argc > 2 ? argv[2] : "v4l2m2m", aus, frames, green, failed);
	chiaki_ffmpeg_decoder_fini(&dec);
	return 0;
}
