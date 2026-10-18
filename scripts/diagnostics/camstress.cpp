// camstress: reproduce GNOME Snapshot's camera usage pattern with libcamera.
//
//   camstress [cycles] [gap_ms]
//
// One CameraManager for the whole run (like PipeWire's libcamera plugin).
// Each cycle: rear 640x480 short start/stop, rear 1280x1080 start/stop
// three times back to back, then front 1280x1080.  A stage that delivers
// fewer frames than wanted within 3 s is reported as STALL and the run stops.
//
// Build (in the noble build chroot, against the libcamera-gts9u tree):
//   g++ -std=c++17 -O2 -o camstress camstress.cpp -I$L/include -I$L/build/include \
//       -L$L/build/src/libcamera -L$L/build/src/libcamera/base -lcamera -lcamera-base
// Stop PipeWire/WirePlumber first; they hold the cameras.
#include <libcamera/libcamera.h>

#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

using namespace libcamera;
using namespace std::chrono_literals;

static std::mutex mtx;
static std::condition_variable cv;
static unsigned int frames;
static Camera *active;

static void requestComplete(Request *request)
{
	if (request->status() == Request::RequestCancelled)
		return;
	{
		std::lock_guard<std::mutex> lock(mtx);
		frames++;
	}
	cv.notify_all();
	request->reuse(Request::ReuseBuffers);
	active->queueRequest(request);
}

static bool runStage(std::shared_ptr<Camera> cam, const char *name, Size size,
		     unsigned int want, bool af)
{
	std::unique_ptr<CameraConfiguration> config =
		cam->generateConfiguration({ StreamRole::Viewfinder });
	StreamConfiguration &sc = config->at(0);
	sc.size = size;
	sc.pixelFormat = formats::ABGR8888;
	sc.bufferCount = 4;
	config->validate();
	if (cam->configure(config.get())) {
		printf("%s: configure failed\n", name);
		return false;
	}

	FrameBufferAllocator alloc(cam);
	Stream *stream = sc.stream();
	if (alloc.allocate(stream) < 0) {
		printf("%s: allocate failed\n", name);
		return false;
	}

	std::vector<std::unique_ptr<Request>> requests;
	for (const std::unique_ptr<FrameBuffer> &buffer : alloc.buffers(stream)) {
		std::unique_ptr<Request> request = cam->createRequest();
		request->addBuffer(stream, buffer.get());
		if (af && cam->controls().count(&controls::AfMode))
			request->controls().set(controls::AfMode, controls::AfModeContinuous);
		requests.push_back(std::move(request));
	}

	frames = 0;
	active = cam.get();
	auto t0 = std::chrono::steady_clock::now();
	if (cam->start()) {
		printf("%-22s start failed\n", name);
		return false;
	}
	for (std::unique_ptr<Request> &request : requests)
		cam->queueRequest(request.get());

	bool ok;
	{
		std::unique_lock<std::mutex> lock(mtx);
		ok = cv.wait_for(lock, 3s, [&] { return frames >= want; });
	}
	unsigned int got = frames;
	cam->stop();
	auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
			  std::chrono::steady_clock::now() - t0).count();
	printf("%-22s %4ux%-4u frames=%3u %5lld ms %s\n", name, sc.size.width,
	       sc.size.height, got, (long long)ms, ok ? "ok" : "STALL");
	fflush(stdout);
	return ok;
}

int main(int argc, char **argv)
{
	unsigned int cycles = argc > 1 ? atoi(argv[1]) : 5;
	unsigned int gap = argc > 2 ? atoi(argv[2]) : 0;

	CameraManager cm;
	cm.start();
	std::shared_ptr<Camera> rear, front;
	for (const std::shared_ptr<Camera> &c : cm.cameras()) {
		if (c->id().find("ac15000") != std::string::npos)
			rear = c;
		else if (c->id().find("ac16000") != std::string::npos)
			front = c;
	}
	if (!rear || !front) {
		printf("cameras not found\n");
		return 1;
	}
	rear->requestCompleted.connect(requestComplete);
	front->requestCompleted.connect(requestComplete);

	bool ok = true;
	for (unsigned int i = 0; i < cycles && ok; i++) {
		printf("-- cycle %u\n", i);
		if (rear->acquire()) {
			printf("rear acquire failed\n");
			return 1;
		}
		ok = runStage(rear, "rear probe", { 640, 480 }, 2, true);
		std::this_thread::sleep_for(std::chrono::milliseconds(gap));
		ok = ok && runStage(rear, "rear view", { 1280, 1080 }, 20, true);
		std::this_thread::sleep_for(std::chrono::milliseconds(gap));
		ok = ok && runStage(rear, "rear restart (photo)", { 1280, 1080 }, 5, true);
		std::this_thread::sleep_for(std::chrono::milliseconds(gap));
		ok = ok && runStage(rear, "rear restart 2", { 1280, 1080 }, 5, true);
		rear->release();
		if (!ok)
			break;
		if (front->acquire()) {
			printf("front acquire failed\n");
			return 1;
		}
		ok = runStage(front, "front view", { 1280, 1080 }, 20, false);
		front->release();
	}
	rear.reset();
	front.reset();
	cm.stop();
	printf(ok ? "RESULT ok\n" : "RESULT STALL\n");
	return ok ? 0 : 2;
}
