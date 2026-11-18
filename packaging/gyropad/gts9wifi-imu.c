/*
 * gts9wifi-imu: stream the tablet's gyroscope and accelerometer to stdout.
 *
 *   gts9wifi-imu [RATE_HZ]        (default 200)
 *
 * One line per sample, flushed:
 *   G <monotonic µs> <x> <y> <z>     rad/s
 *   A <monotonic µs> <x> <y> <z>     m/s²
 * in the sensor's own axes (libssc applies the mount matrix it has; on this
 * tablet the firmware's is all zero, so identity).
 *
 * The sensors are on the Qualcomm Sensor Core (ADSP), read through libssc.
 * libssc always asked the Sensor Core for the lowest rate a sensor offers
 * (26 Hz for the LSM6DSO here), too slow for motion controls; the copy of
 * libssc built next to this program (build-gyropad.sh) picks the rate given
 * in SSC_SAMPLE_RATE, which this program sets from RATE_HZ.
 */
#include <libssc.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

static long long now_us(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * 1000000LL + ts.tv_nsec / 1000;
}

static void on_gyro(SSCSensorGyroscope *s, gfloat x, gfloat y, gfloat z, gpointer d)
{
	(void)s; (void)d;
	printf("G %lld %.6f %.6f %.6f\n", now_us(), x, y, z);
	fflush(stdout);
}

static void on_accel(SSCSensorAccelerometer *s, gfloat x, gfloat y, gfloat z, gpointer d)
{
	(void)s; (void)d;
	printf("A %lld %.6f %.6f %.6f\n", now_us(), x, y, z);
	fflush(stdout);
}

int main(int argc, char **argv)
{
	const char *rate = argc > 1 ? argv[1] : "200";
	GError *err = NULL;
	SSCSensorGyroscope *gyro;
	SSCSensorAccelerometer *accel;
	GMainLoop *loop;

	g_setenv("SSC_SAMPLE_RATE", rate, TRUE);

	gyro = ssc_sensor_gyroscope_new_sync(NULL, &err);
	if (!gyro) {
		fprintf(stderr, "gyroscope: %s\n", err->message);
		return 1;
	}
	accel = ssc_sensor_accelerometer_new_sync(NULL, &err);
	if (!accel) {
		fprintf(stderr, "accelerometer: %s\n", err->message);
		return 1;
	}
	g_signal_connect(gyro, "measurement", G_CALLBACK(on_gyro), NULL);
	g_signal_connect(accel, "measurement", G_CALLBACK(on_accel), NULL);
	if (!ssc_sensor_gyroscope_open_sync(gyro, NULL, &err) ||
	    !ssc_sensor_accelerometer_open_sync(accel, NULL, &err)) {
		fprintf(stderr, "open: %s\n", err->message);
		return 1;
	}
	fprintf(stderr, "gts9wifi-imu: streaming (asked for %s Hz)\n", rate);
	loop = g_main_loop_new(NULL, FALSE);
	g_main_loop_run(loop);
	return 0;
}
