/* Feeds an H.264 file to a decoder the way chiaki-ng does (one access unit
 * per "network frame", send then pull-all), paced at 60 fps, and reports
 * frames out, dropped packets and the mean luma of output frames.
 *   m2mtest FILE DECODER [mode]   mode: chiaki (default) | fixed
 * W=1920 H=1080 opens the decoder with that size (what patch 0001 does);
 * CHIAKI_CTX=1 sets chiaki-ng's timebases and packet timestamps;
 * SPLIT=1 sends the first unit's SPS/PPS as a packet of their own, as the
 * PS5 stream does; TRACE=1 prints every access unit, AVLOG=<level> FFmpeg's
 * log level.  Build on the tablet:
 *   gcc -O2 -o m2mtest m2mtest.c $(pkg-config --cflags --libs libavcodec libavutil)
 * Input like a PS5 stream (no B-frames):
 *   ffmpeg -f lavfi -i testsrc2=size=1920x1080:rate=60 -t 5 -c:v libx264 \
 *     -preset ultrafast -tune zerolatency -b:v 30M -g 600 ps.h264 */
#include <libavcodec/avcodec.h>
#include <libavutil/log.h>
#include <libavutil/pixdesc.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static double luma_mean(const AVFrame *f)
{
	if(!f->data[0])
		return -1;
	long sum = 0, n = 0;
	for(int y = 0; y < f->height; y += 16)
		for(int x = 0; x < f->width; x += 16, n++)
			sum += f->data[0][y * f->linesize[0] + x];
	return n ? (double)sum / n : -1;
}

int main(int argc, char **argv)
{
	const char *mode = argc > 3 ? argv[3] : "chiaki";
	av_log_set_level(getenv("AVLOG") ? atoi(getenv("AVLOG")) : AV_LOG_WARNING);
	FILE *fp = fopen(argv[1], "rb");
	fseek(fp, 0, SEEK_END); long len = ftell(fp); fseek(fp, 0, SEEK_SET);
	uint8_t *data = malloc(len + AV_INPUT_BUFFER_PADDING_SIZE);
	fread(data, 1, len, fp);
	memset(data + len, 0, AV_INPUT_BUFFER_PADDING_SIZE);

	const AVCodec *codec = avcodec_find_decoder_by_name(argv[2]);
	AVCodecContext *ctx = avcodec_alloc_context3(codec);
	if(getenv("W")) { ctx->width = atoi(getenv("W")); ctx->height = atoi(getenv("H")); }
	if(getenv("CHIAKI_CTX")) { ctx->framerate = (AVRational){60,1}; ctx->pkt_timebase = (AVRational){1,1000000}; ctx->time_base = (AVRational){1,1000000}; }
	if(avcodec_open2(ctx, codec, NULL) < 0) { fprintf(stderr, "open failed\n"); return 1; }
	AVCodecParserContext *parser = av_parser_init(AV_CODEC_ID_H264);
	AVCodecContext *pctx = avcodec_alloc_context3(NULL);

	int aus = 0, out = 0, dropped = 0, fail = 0, eagain_both = 0;
	double first_luma = -2, last_luma = -2;
	long off = 0;
	AVFrame *frame = av_frame_alloc();
	while(off < len)
	{
		uint8_t *au; int au_size;
		int used = av_parser_parse2(parser, pctx, &au, &au_size, data + off, len - off, AV_NOPTS_VALUE, AV_NOPTS_VALUE, 0);
		off += used;
		if(!au_size)
			continue;
		aus++; if(getenv("TRACE")) fprintf(stderr, "AU %d size %d out %d dropped %d\n", aus, au_size, out, dropped);
		if(aus == 1 && getenv("SPLIT"))
		{
			/* like chiaki-ng: parameter sets (SPS/PPS) as a packet of their own */
			int cut = 0;
			for(int i = 0; i + 4 < au_size; i++)
				if(au[i] == 0 && au[i + 1] == 0 && au[i + 2] == 1 && ((au[i + 3] & 0x1f) == 5 || (au[i + 3] & 0x1f) == 6))
				{
					cut = i > 0 && au[i - 1] == 0 ? i - 1 : i;
					break;
				}
			fprintf(stderr, "split first AU %d -> %d + %d\n", au_size, cut, au_size - cut);
			AVPacket *hp = av_packet_alloc();
			av_new_packet(hp, cut);
			memcpy(hp->data, au, cut);
			fprintf(stderr, "header send %d\n", avcodec_send_packet(ctx, hp));
			av_packet_free(&hp);
			while(avcodec_receive_frame(ctx, frame) == 0)
				out++;
			au += cut;
			au_size -= cut;
		}
		AVPacket *pkt = av_packet_alloc();
		av_new_packet(pkt, au_size);
		memcpy(pkt->data, au, au_size);
		pkt->pts = pkt->dts = aus;
		for(;;)
		{
			int r = avcodec_send_packet(ctx, pkt);
			if(r == 0)
				break;
			if(r != AVERROR(EAGAIN)) { fail++; break; }
			if(!strcmp(mode, "fixed"))
			{
				/* wait for the decoder to take the packet: pull frames */
				r = avcodec_receive_frame(ctx, frame);
				if(r == 0) { out++; last_luma = luma_mean(frame); if(first_luma < -1) first_luma = last_luma; av_frame_unref(frame); }
				else usleep(1000);
				continue;
			}
			r = avcodec_receive_frame(ctx, frame);
			if(r) { eagain_both++; dropped++; break; }
			av_frame_unref(frame);
			dropped++;
		}
		av_packet_free(&pkt);
		while(avcodec_receive_frame(ctx, frame) == 0)
		{
			out++;
			last_luma = luma_mean(frame);
			if(first_luma < -1) first_luma = last_luma;
			av_frame_unref(frame);
		}
		usleep(16000);
	}
	printf("%s %s: AUs %d, frames out %d, packets dropped %d (receive also EAGAIN: %d), send errors %d, luma first %.1f last %.1f, fmt %s %dx%d\n",
		argv[2], mode, aus, out, dropped, eagain_both, fail, first_luma, last_luma,
		av_get_pix_fmt_name(ctx->pix_fmt) ? av_get_pix_fmt_name(ctx->pix_fmt) : "?", ctx->width, ctx->height);
	return 0;
}
