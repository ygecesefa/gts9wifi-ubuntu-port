/* Zero-copy feasibility: can a frame the iris decoder made go to Vulkan
 * (Turnip) without a copy?
 *
 * Decodes an Annex-B H.264 file with the V4L2 stateful decoder (no FFmpeg),
 * exports the N-th picture as a dmabuf (VIDIOC_EXPBUF), imports that dmabuf
 * into Vulkan and reads the picture back through Vulkan, comparing it with
 * the decoder's own mapping of the buffer.  Two ways to import, as the two
 * kinds of consumer do:
 *   planes: one R8 image for Y and one R8G8 image for UV, each at its offset
 *           in the dmabuf (libplacebo: chiaki-ng, mpv)
 *   nv12:   one G8_B8R8_2PLANE_420 image (FFmpeg's Vulkan hwcontext,
 *           GStreamer; sampled through a Y'CbCr conversion)
 * It also times what the copy path costs now (memcpy of the frame out of
 * the decoder's mapping) against the import.
 *
 *   dmabuf-vulkan FILE.h264 [FRAME_NO [OUT.nv12]]
 * DEV=/dev/videoN picks the decoder (default: the first iris_driver node that
 * takes H.264), W= H= the size to open it with (default 1920x1080),
 * UVOFF= the UV plane's offset if the guess (stride x coded height) is wrong.
 * BENCH=<seconds> instead decodes the file in a loop at 60 pictures a second
 * and reports the CPU time the process took; with COPY=<n> every picture is
 * also copied out of the decoder buffer n times (FFmpeg's v4l2m2m copies once,
 * the upload to the GPU is a second pass over the data).
 * OUT.nv12 gets the picture as Vulkan read it (tightly packed NV12):
 *   ffmpeg -f rawvideo -pix_fmt nv12 -s 1920x1080 -i out.nv12 out.png
 *
 * Input: one slice per picture, no B-frames (as the PS5 sends):
 *   ffmpeg -f lavfi -i testsrc2=size=1920x1080:rate=60 -t 2 -c:v libx264 \
 *     -preset ultrafast -tune zerolatency -x264-params slices=1:sliced-threads=0 \
 *     -g 600 -bsf:v h264_mp4toannexb ps.h264
 * Build (the Vulkan loader is opened at run time, only headers are needed):
 *   gcc -O2 -o dmabuf-vulkan dmabuf-vulkan.c -ldl */
#define _GNU_SOURCE
#define VK_NO_PROTOTYPES
#include <vulkan/vulkan.h>
#include <linux/videodev2.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <time.h>
#include <unistd.h>

#define DIE(...) do { fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n"); exit(1); } while(0)
#define ALIGN(x, a) (((x) + (a) - 1) & ~((a) - 1))

static double now(void)
{
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec + t.tv_nsec / 1e9;
}

/* ---------- Vulkan, loaded at run time ---------- */
#define VKFUNCS(X) \
	X(vkCreateInstance) X(vkEnumeratePhysicalDevices) X(vkGetPhysicalDeviceProperties) \
	X(vkGetPhysicalDeviceQueueFamilyProperties) X(vkCreateDevice) X(vkGetDeviceQueue) \
	X(vkGetPhysicalDeviceImageFormatProperties2) X(vkGetPhysicalDeviceFormatProperties2) \
	X(vkCreateImage) X(vkGetImageMemoryRequirements) X(vkAllocateMemory) X(vkBindImageMemory) \
	X(vkCreateBuffer) X(vkGetBufferMemoryRequirements) X(vkGetPhysicalDeviceMemoryProperties) \
	X(vkBindBufferMemory) X(vkMapMemory) X(vkCreateCommandPool) X(vkAllocateCommandBuffers) \
	X(vkBeginCommandBuffer) X(vkCmdPipelineBarrier) X(vkCmdCopyImageToBuffer) X(vkEndCommandBuffer) \
	X(vkQueueSubmit) X(vkQueueWaitIdle) X(vkDestroyImage) X(vkFreeMemory) X(vkGetDeviceProcAddr) \
	X(vkResetCommandBuffer)
#define X(n) static PFN_##n n;
VKFUNCS(X)
#undef X
static PFN_vkGetMemoryFdPropertiesKHR vkGetMemoryFdPropertiesKHR_;

static VkPhysicalDevice phys;
static VkDevice dev;
static VkQueue queue;
static VkCommandBuffer cmd;
static VkBuffer rbuf;
static uint8_t *rmap;
static VkPhysicalDeviceMemoryProperties memprops;

#define CHK(call) do { VkResult r_ = (call); if(r_ != VK_SUCCESS) DIE("%s: VkResult %d", #call, r_); } while(0)

static void vk_init(size_t readback_size)
{
	void *lib = dlopen("libvulkan.so.1", RTLD_NOW);
	if(!lib) DIE("libvulkan.so.1: %s", dlerror());
#define X(n) if(!(n = (PFN_##n)dlsym(lib, #n))) DIE("no %s", #n);
	VKFUNCS(X)
#undef X
	VkApplicationInfo app = { VK_STRUCTURE_TYPE_APPLICATION_INFO, .apiVersion = VK_API_VERSION_1_1 };
	VkInstanceCreateInfo ici = { VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo = &app };
	VkInstance inst;
	CHK(vkCreateInstance(&ici, NULL, &inst));
	VkPhysicalDevice pds[8]; uint32_t n = 8;
	vkEnumeratePhysicalDevices(inst, &n, pds);
	for(uint32_t i = 0; i < n && !phys; i++) {
		VkPhysicalDeviceProperties p;
		vkGetPhysicalDeviceProperties(pds[i], &p);
		if(p.deviceType != VK_PHYSICAL_DEVICE_TYPE_CPU) {
			phys = pds[i];
			printf("vulkan: %s\n", p.deviceName);
		}
	}
	if(!phys) DIE("no GPU Vulkan device");
	VkQueueFamilyProperties qf[8]; uint32_t nq = 8, qi = 0;
	vkGetPhysicalDeviceQueueFamilyProperties(phys, &nq, qf);
	while(qi < nq && !(qf[qi].queueFlags & VK_QUEUE_GRAPHICS_BIT)) qi++;
	float prio = 1;
	VkDeviceQueueCreateInfo qci = { VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, .queueFamilyIndex = qi, .queueCount = 1, .pQueuePriorities = &prio };
	const char *exts[] = { "VK_KHR_external_memory_fd", "VK_EXT_external_memory_dma_buf",
		"VK_EXT_image_drm_format_modifier", "VK_KHR_image_format_list", "VK_EXT_queue_family_foreign" };
	VkDeviceCreateInfo dci = { VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, .queueCreateInfoCount = 1, .pQueueCreateInfos = &qci,
		.enabledExtensionCount = 5, .ppEnabledExtensionNames = exts };
	CHK(vkCreateDevice(phys, &dci, NULL, &dev));
	vkGetDeviceQueue(dev, qi, 0, &queue);
	vkGetMemoryFdPropertiesKHR_ = (PFN_vkGetMemoryFdPropertiesKHR)vkGetDeviceProcAddr(dev, "vkGetMemoryFdPropertiesKHR");
	vkGetPhysicalDeviceMemoryProperties(phys, &memprops);

	VkCommandPoolCreateInfo cpi = { VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO, .flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT, .queueFamilyIndex = qi };
	VkCommandPool pool;
	CHK(vkCreateCommandPool(dev, &cpi, NULL, &pool));
	VkCommandBufferAllocateInfo cai = { VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, .commandPool = pool, .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1 };
	CHK(vkAllocateCommandBuffers(dev, &cai, &cmd));

	VkBufferCreateInfo bci = { VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, .size = readback_size, .usage = VK_BUFFER_USAGE_TRANSFER_DST_BIT };
	CHK(vkCreateBuffer(dev, &bci, NULL, &rbuf));
	VkMemoryRequirements mr;
	vkGetBufferMemoryRequirements(dev, rbuf, &mr);
	uint32_t ti = 0;
	VkMemoryPropertyFlags want = VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
	while(ti < memprops.memoryTypeCount && !((mr.memoryTypeBits >> ti & 1) && (memprops.memoryTypes[ti].propertyFlags & want) == want)) ti++;
	VkMemoryAllocateInfo mai = { VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .allocationSize = mr.size, .memoryTypeIndex = ti };
	VkDeviceMemory bm;
	CHK(vkAllocateMemory(dev, &mai, NULL, &bm));
	CHK(vkBindBufferMemory(dev, rbuf, bm, 0));
	CHK(vkMapMemory(dev, bm, 0, VK_WHOLE_SIZE, 0, (void **)&rmap));
}

static void list_modifiers(VkFormat f, const char *name)
{
	VkDrmFormatModifierPropertiesEXT m[32];
	VkDrmFormatModifierPropertiesListEXT l = { VK_STRUCTURE_TYPE_DRM_FORMAT_MODIFIER_PROPERTIES_LIST_EXT, .drmFormatModifierCount = 32, .pDrmFormatModifierProperties = m };
	VkFormatProperties2 p = { VK_STRUCTURE_TYPE_FORMAT_PROPERTIES_2, .pNext = &l };
	vkGetPhysicalDeviceFormatProperties2(phys, f, &p);
	printf("  %s modifiers:", name);
	for(uint32_t i = 0; i < l.drmFormatModifierCount; i++)
		printf(" 0x%llx(planes %u, features 0x%x)", (unsigned long long)m[i].drmFormatModifier, m[i].drmFormatModifierPlaneCount, m[i].drmFormatModifierTilingFeatures);
	printf("%s\n", l.drmFormatModifierCount ? "" : " none");
}

struct vkimg { VkImage img; VkDeviceMemory mem; };

/* Import `fd` as an image of `fmt`, its planes at offs[]/stride.  0 on success. */
static int import_image(int fd, VkFormat fmt, uint32_t w, uint32_t h, int nplanes, const uint64_t *offs, uint32_t stride, struct vkimg *out, int verbose)
{
	VkImageUsageFlags usage = VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
	VkPhysicalDeviceImageDrmFormatModifierInfoEXT mi = { VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_DRM_FORMAT_MODIFIER_INFO_EXT, .drmFormatModifier = 0, .sharingMode = VK_SHARING_MODE_EXCLUSIVE };
	VkPhysicalDeviceExternalImageFormatInfo ei = { VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_EXTERNAL_IMAGE_FORMAT_INFO, .pNext = &mi, .handleType = VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT };
	VkPhysicalDeviceImageFormatInfo2 fi = { VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_IMAGE_FORMAT_INFO_2, .pNext = &ei, .format = fmt, .type = VK_IMAGE_TYPE_2D,
		.tiling = VK_IMAGE_TILING_DRM_FORMAT_MODIFIER_EXT, .usage = usage };
	VkExternalImageFormatProperties ep = { VK_STRUCTURE_TYPE_EXTERNAL_IMAGE_FORMAT_PROPERTIES };
	VkImageFormatProperties2 fp = { VK_STRUCTURE_TYPE_IMAGE_FORMAT_PROPERTIES_2, .pNext = &ep };
	VkResult r = vkGetPhysicalDeviceImageFormatProperties2(phys, &fi, &fp);
	if(verbose)
		printf("  format query: VkResult %d, external features 0x%x (importable: %s)\n", r, ep.externalMemoryProperties.externalMemoryFeatures,
			ep.externalMemoryProperties.externalMemoryFeatures & VK_EXTERNAL_MEMORY_FEATURE_IMPORTABLE_BIT ? "yes" : "no");
	if(r != VK_SUCCESS) return -1;

	VkSubresourceLayout pl[2] = {0};
	for(int i = 0; i < nplanes; i++) { pl[i].offset = offs[i]; pl[i].rowPitch = stride; }
	VkImageDrmFormatModifierExplicitCreateInfoEXT xi = { VK_STRUCTURE_TYPE_IMAGE_DRM_FORMAT_MODIFIER_EXPLICIT_CREATE_INFO_EXT, .drmFormatModifier = 0,
		.drmFormatModifierPlaneCount = nplanes, .pPlaneLayouts = pl };
	VkExternalMemoryImageCreateInfo xm = { VK_STRUCTURE_TYPE_EXTERNAL_MEMORY_IMAGE_CREATE_INFO, .pNext = &xi, .handleTypes = VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT };
	VkImageCreateInfo ci = { VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO, .pNext = &xm, .imageType = VK_IMAGE_TYPE_2D, .format = fmt, .extent = { w, h, 1 },
		.mipLevels = 1, .arrayLayers = 1, .samples = VK_SAMPLE_COUNT_1_BIT, .tiling = VK_IMAGE_TILING_DRM_FORMAT_MODIFIER_EXT, .usage = usage,
		.sharingMode = VK_SHARING_MODE_EXCLUSIVE, .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED };
	r = vkCreateImage(dev, &ci, NULL, &out->img);
	if(r != VK_SUCCESS) { if(verbose) printf("  vkCreateImage: VkResult %d\n", r); return -1; }
	VkMemoryRequirements mr;
	vkGetImageMemoryRequirements(dev, out->img, &mr);
	VkMemoryFdPropertiesKHR fdp = { VK_STRUCTURE_TYPE_MEMORY_FD_PROPERTIES_KHR };
	r = vkGetMemoryFdPropertiesKHR_(dev, VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT, fd, &fdp);
	if(r != VK_SUCCESS) { if(verbose) printf("  vkGetMemoryFdPropertiesKHR: VkResult %d\n", r); return -1; }
	uint32_t bits = fdp.memoryTypeBits & mr.memoryTypeBits, ti = 0;
	if(!bits) { if(verbose) printf("  no common memory type (fd 0x%x, image 0x%x)\n", fdp.memoryTypeBits, mr.memoryTypeBits); return -1; }
	while(!(bits >> ti & 1)) ti++;
	off_t size = lseek(fd, 0, SEEK_END);
	if(verbose) printf("  image needs %llu bytes, dmabuf has %lld\n", (unsigned long long)mr.size, (long long)size);
	VkImportMemoryFdInfoKHR imp = { VK_STRUCTURE_TYPE_IMPORT_MEMORY_FD_INFO_KHR, .handleType = VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT, .fd = dup(fd) };
	VkMemoryAllocateInfo ai = { VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .pNext = &imp, .allocationSize = size, .memoryTypeIndex = ti };
	r = vkAllocateMemory(dev, &ai, NULL, &out->mem);
	if(r != VK_SUCCESS) { if(verbose) printf("  vkAllocateMemory (import): VkResult %d\n", r); close(imp.fd); return -1; }
	r = vkBindImageMemory(dev, out->img, out->mem, 0);
	if(r != VK_SUCCESS) { if(verbose) printf("  vkBindImageMemory: VkResult %d\n", r); return -1; }
	return 0;
}

/* Copy one aspect of the image to the read-back buffer at `boff`. */
static void read_back(VkImage img, VkImageAspectFlags aspect, uint32_t w, uint32_t h, VkDeviceSize boff, int first)
{
	vkResetCommandBuffer(cmd, 0);
	VkCommandBufferBeginInfo bi = { VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO, .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT };
	CHK(vkBeginCommandBuffer(cmd, &bi));
	if(first) {
		VkImageMemoryBarrier b = { VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER, .dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT,
			.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED, .newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
			.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED, .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED, .image = img,
			.subresourceRange = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1 } };
		vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, NULL, 0, NULL, 1, &b);
	}
	VkBufferImageCopy c = { .bufferOffset = boff, .imageSubresource = { aspect, 0, 0, 1 }, .imageExtent = { w, h, 1 } };
	vkCmdCopyImageToBuffer(cmd, img, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, rbuf, 1, &c);
	CHK(vkEndCommandBuffer(cmd));
	VkSubmitInfo si = { VK_STRUCTURE_TYPE_SUBMIT_INFO, .commandBufferCount = 1, .pCommandBuffers = &cmd };
	CHK(vkQueueSubmit(queue, 1, &si, VK_NULL_HANDLE));
	CHK(vkQueueWaitIdle(queue));
}

/* Compare the tightly packed read-back with the decoder's mapping. */
static long diff_planes(const uint8_t *map, uint32_t stride, uint64_t uvoff, uint32_t w, uint32_t h)
{
	long bad = 0;
	for(uint32_t y = 0; y < h; y++)
		for(uint32_t x = 0; x < w; x++)
			bad += rmap[y * w + x] != map[y * stride + x];
	const uint8_t *uv = rmap + (size_t)w * h;
	for(uint32_t y = 0; y < h / 2; y++)
		for(uint32_t x = 0; x < w; x++)
			bad += uv[y * w + x] != map[uvoff + y * stride + x];
	return bad;
}

/* ---------- V4L2 stateful decoder ---------- */
#define OUT V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE
#define CAP V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE

static int xioctl(int fd, unsigned long req, void *arg)
{
	int r;
	do r = ioctl(fd, req, arg); while(r < 0 && errno == EINTR);
	return r;
}

static int find_decoder(void)
{
	if(getenv("DEV")) return open(getenv("DEV"), O_RDWR | O_NONBLOCK);
	for(int i = 0; i < 64; i++) {
		char p[32];
		snprintf(p, sizeof p, "/dev/video%d", i);
		int fd = open(p, O_RDWR | O_NONBLOCK);
		if(fd < 0) continue;
		struct v4l2_capability c;
		if(!xioctl(fd, VIDIOC_QUERYCAP, &c) && !strcmp((char *)c.driver, "iris_driver")) {
			struct v4l2_fmtdesc d = { .type = OUT };
			for(; !xioctl(fd, VIDIOC_ENUM_FMT, &d); d.index++)
				if(d.pixelformat == V4L2_PIX_FMT_H264) { printf("decoder: %s (%s)\n", p, c.card); return fd; }
		}
		close(fd);
	}
	return -1;
}

static const uint8_t *next_start(const uint8_t *p, const uint8_t *end)
{
	for(; p + 3 <= end; p++)
		if(!p[0] && !p[1] && p[2] == 1) return p;
	return end;
}

/* One access unit: everything up to and including the first slice NAL. */
static const uint8_t *next_au(const uint8_t *p, const uint8_t *end)
{
	const uint8_t *s = next_start(p, end);
	while(s < end) {
		int type = s[3] & 0x1f;
		const uint8_t *n = next_start(s + 3, end);
		if(n < end && n > p && n[-1] == 0) n--; /* 4-byte start code belongs to the next NAL */
		if(type == 1 || type == 5) return n;
		s = next_start(n, end);
	}
	return end;
}

#define NOUT 4
#define NCAP_MAX 32
static struct { uint8_t *map; size_t len; int busy; } ob[NOUT];
static struct { uint8_t *map; size_t len; } cb[NCAP_MAX];
static int ncap, cap_on;
static struct v4l2_format capfmt;

static void setup_capture(int fd)
{
	int t = CAP;
	if(cap_on) {
		xioctl(fd, VIDIOC_STREAMOFF, &t);
		for(int i = 0; i < ncap; i++) munmap(cb[i].map, cb[i].len);
		struct v4l2_requestbuffers z = { .type = CAP, .memory = V4L2_MEMORY_MMAP };
		xioctl(fd, VIDIOC_REQBUFS, &z);
		cap_on = 0;
	}
	capfmt = (struct v4l2_format){ .type = CAP };
	if(xioctl(fd, VIDIOC_G_FMT, &capfmt)) DIE("G_FMT capture: %s", strerror(errno));
	capfmt.fmt.pix_mp.pixelformat = V4L2_PIX_FMT_NV12;
	if(xioctl(fd, VIDIOC_S_FMT, &capfmt)) DIE("S_FMT capture: %s", strerror(errno));
	struct v4l2_control mc = { .id = V4L2_CID_MIN_BUFFERS_FOR_CAPTURE };
	int min = xioctl(fd, VIDIOC_G_CTRL, &mc) ? 4 : mc.value;
	struct v4l2_requestbuffers rb = { .count = min + 4, .type = CAP, .memory = V4L2_MEMORY_MMAP };
	if(xioctl(fd, VIDIOC_REQBUFS, &rb)) DIE("REQBUFS capture: %s", strerror(errno));
	ncap = rb.count > NCAP_MAX ? NCAP_MAX : rb.count;
	for(int i = 0; i < ncap; i++) {
		struct v4l2_plane pl = {0};
		struct v4l2_buffer b = { .type = CAP, .memory = V4L2_MEMORY_MMAP, .index = i, .length = 1, .m.planes = &pl };
		if(xioctl(fd, VIDIOC_QUERYBUF, &b)) DIE("QUERYBUF capture: %s", strerror(errno));
		cb[i].len = pl.length;
		cb[i].map = mmap(NULL, pl.length, PROT_READ, MAP_SHARED, fd, pl.m.mem_offset);
		if(cb[i].map == MAP_FAILED) DIE("mmap capture: %s", strerror(errno));
		if(xioctl(fd, VIDIOC_QBUF, &b)) DIE("QBUF capture: %s", strerror(errno));
	}
	if(xioctl(fd, VIDIOC_STREAMON, &t)) DIE("STREAMON capture: %s", strerror(errno));
	cap_on = 1;
	struct v4l2_pix_format_mplane *m = &capfmt.fmt.pix_mp;
	printf("capture: %ux%u %.4s, %u plane(s), stride %u, sizeimage %u, %d buffers (min %d)\n", m->width, m->height,
		(char *)&m->pixelformat, m->num_planes, m->plane_fmt[0].bytesperline, m->plane_fmt[0].sizeimage, ncap, min);
}

static int test_frame(int fd, int index, uint32_t vis_w, uint32_t vis_h, const char *dump)
{
	struct v4l2_pix_format_mplane *m = &capfmt.fmt.pix_mp;
	uint32_t stride = m->plane_fmt[0].bytesperline;
	struct v4l2_selection sel = { .type = V4L2_BUF_TYPE_VIDEO_CAPTURE, .target = V4L2_SEL_TGT_COMPOSE };
	if(!xioctl(fd, VIDIOC_G_SELECTION, &sel) && sel.r.width) { vis_w = sel.r.width; vis_h = sel.r.height; }
	uint32_t w = vis_w, h = vis_h;
	uint64_t uvoff = getenv("UVOFF") ? strtoull(getenv("UVOFF"), NULL, 0) : (uint64_t)stride * (m->height >= ALIGN(h, 32) ? m->height : ALIGN(h, 32));
	printf("picture: visible %ux%u, Y at 0, UV at %llu, stride %u\n", w, h, (unsigned long long)uvoff, stride);

	struct v4l2_exportbuffer ex = { .type = CAP, .index = index, .plane = 0, .flags = O_RDONLY | O_CLOEXEC };
	if(xioctl(fd, VIDIOC_EXPBUF, &ex)) { printf("RESULT: VIDIOC_EXPBUF failed: %s (the decoder gives no dmabuf)\n", strerror(errno)); return 1; }
	printf("dmabuf: fd %d, %lld bytes\n", ex.fd, (long long)lseek(ex.fd, 0, SEEK_END));

	size_t tight = (size_t)w * h * 3 / 2;
	vk_init(tight);
	list_modifiers(VK_FORMAT_R8_UNORM, "R8");
	list_modifiers(VK_FORMAT_R8G8_UNORM, "R8G8");
	list_modifiers(VK_FORMAT_G8_B8R8_2PLANE_420_UNORM, "NV12");
	const uint8_t *map = cb[index].map;
	int ok = 0;

	printf("import as planes (R8 + R8G8, the libplacebo way):\n");
	struct vkimg y, uv;
	uint64_t o0 = 0;
	if(!import_image(ex.fd, VK_FORMAT_R8_UNORM, w, h, 1, &o0, stride, &y, 1) &&
	   !import_image(ex.fd, VK_FORMAT_R8G8_UNORM, w / 2, h / 2, 1, &uvoff, stride, &uv, 1)) {
		memset(rmap, 0, tight);
		read_back(y.img, VK_IMAGE_ASPECT_COLOR_BIT, w, h, 0, 1);
		read_back(uv.img, VK_IMAGE_ASPECT_COLOR_BIT, w / 2, h / 2, (size_t)w * h, 1);
		long bad = diff_planes(map, stride, uvoff, w, h);
		printf("  RESULT planes: %s (%ld of %zu bytes differ)\n", bad ? "MISMATCH" : "IDENTICAL", bad, tight);
		ok |= !bad;
		if(dump) { FILE *f = fopen(dump, "wb"); fwrite(rmap, 1, tight, f); fclose(f); }
		vkDestroyImage(dev, y.img, NULL); vkFreeMemory(dev, y.mem, NULL);
		vkDestroyImage(dev, uv.img, NULL); vkFreeMemory(dev, uv.mem, NULL);
	} else
		printf("  RESULT planes: IMPORT FAILED\n");

	printf("import as one NV12 image (G8_B8R8_2PLANE_420):\n");
	struct vkimg nv;
	uint64_t offs[2] = { 0, uvoff };
	if(!import_image(ex.fd, VK_FORMAT_G8_B8R8_2PLANE_420_UNORM, w, h, 2, offs, stride, &nv, 1)) {
		memset(rmap, 0, tight);
		read_back(nv.img, VK_IMAGE_ASPECT_PLANE_0_BIT, w, h, 0, 1);
		read_back(nv.img, VK_IMAGE_ASPECT_PLANE_1_BIT, w / 2, h / 2, (size_t)w * h, 0);
		long bad = diff_planes(map, stride, uvoff, w, h);
		printf("  RESULT nv12: %s (%ld of %zu bytes differ)\n", bad ? "MISMATCH" : "IDENTICAL", bad, tight);
		vkDestroyImage(dev, nv.img, NULL); vkFreeMemory(dev, nv.mem, NULL);
	} else
		printf("  RESULT nv12: IMPORT FAILED\n");

	/* What each path costs per frame. */
	uint8_t *tmp = malloc(tight);
	double t0 = now();
	for(int i = 0; i < 30; i++) {
		for(uint32_t r = 0; r < h; r++) memcpy(tmp + r * w, map + r * stride, w);
		for(uint32_t r = 0; r < h / 2; r++) memcpy(tmp + (size_t)w * h + r * w, map + uvoff + r * stride, w);
	}
	double copy_ms = (now() - t0) / 30 * 1e3;
	long sum = 0;
	for(size_t i = 0; i < tight; i += 4096) sum += tmp[i];
	free(tmp);
	t0 = now();
	int n = 0;
	for(; n < 30; n++) {
		if(import_image(ex.fd, VK_FORMAT_R8_UNORM, w, h, 1, &o0, stride, &y, 0) ||
		   import_image(ex.fd, VK_FORMAT_R8G8_UNORM, w / 2, h / 2, 1, &uvoff, stride, &uv, 0)) break;
		vkDestroyImage(dev, y.img, NULL); vkFreeMemory(dev, y.mem, NULL);
		vkDestroyImage(dev, uv.img, NULL); vkFreeMemory(dev, uv.mem, NULL);
	}
	if(n)
		printf("cost per frame: copy out of the decoder buffer %.2f ms (the upload to the GPU comes on top); import of both planes %.3f ms (sum %ld)\n",
			copy_ms, (now() - t0) / n * 1e3, sum);
	return !ok;
}

int main(int argc, char **argv)
{
	if(argc < 2) DIE("usage: %s FILE.h264 [FRAME_NO [OUT.nv12]]", argv[0]);
	int target = argc > 2 ? atoi(argv[2]) : 30;
	uint32_t w = getenv("W") ? atoi(getenv("W")) : 1920, h = getenv("H") ? atoi(getenv("H")) : 1080;
	setvbuf(stdout, NULL, _IOLBF, 0);

	FILE *fp = fopen(argv[1], "rb");
	if(!fp) DIE("%s: %s", argv[1], strerror(errno));
	fseek(fp, 0, SEEK_END); long len = ftell(fp); fseek(fp, 0, SEEK_SET);
	uint8_t *data = malloc(len);
	if(fread(data, 1, len, fp) != (size_t)len) DIE("read");
	const uint8_t *pos = data, *end = data + len;

	int fd = find_decoder();
	if(fd < 0) DIE("no H.264 decoder");
	struct v4l2_event_subscription sub = { .type = V4L2_EVENT_SOURCE_CHANGE };
	xioctl(fd, VIDIOC_SUBSCRIBE_EVENT, &sub);

	struct v4l2_format of = { .type = OUT };
	of.fmt.pix_mp.pixelformat = V4L2_PIX_FMT_H264;
	of.fmt.pix_mp.width = w; of.fmt.pix_mp.height = h; of.fmt.pix_mp.num_planes = 1;
	of.fmt.pix_mp.plane_fmt[0].sizeimage = 2 << 20;
	if(xioctl(fd, VIDIOC_S_FMT, &of)) DIE("S_FMT output: %s", strerror(errno));
	struct v4l2_requestbuffers rb = { .count = NOUT, .type = OUT, .memory = V4L2_MEMORY_MMAP };
	if(xioctl(fd, VIDIOC_REQBUFS, &rb) || rb.count < NOUT) DIE("REQBUFS output: %s", strerror(errno));
	for(int i = 0; i < NOUT; i++) {
		struct v4l2_plane pl = {0};
		struct v4l2_buffer b = { .type = OUT, .memory = V4L2_MEMORY_MMAP, .index = i, .length = 1, .m.planes = &pl };
		if(xioctl(fd, VIDIOC_QUERYBUF, &b)) DIE("QUERYBUF output: %s", strerror(errno));
		ob[i].len = pl.length;
		ob[i].map = mmap(NULL, pl.length, PROT_READ | PROT_WRITE, MAP_SHARED, fd, pl.m.mem_offset);
		if(ob[i].map == MAP_FAILED) DIE("mmap output: %s", strerror(errno));
	}
	int t = OUT;
	if(xioctl(fd, VIDIOC_STREAMON, &t)) DIE("STREAMON output: %s", strerror(errno));

	int fed = 0, got = 0, queued = 0;
	double start = now();
	double bench = getenv("BENCH") ? atof(getenv("BENCH")) : 0;
	int copies = getenv("COPY") ? atoi(getenv("COPY")) : 0;
	uint8_t *tmp = bench ? malloc((size_t)w * (h + 32) * 3 / 2) : NULL;
	if(bench) target = -1;
	for(;;) {
		if(bench && pos >= end) pos = data;
		if(bench && now() - start > bench) {
			struct rusage ru;
			getrusage(RUSAGE_SELF, &ru);
			double cpu = ru.ru_utime.tv_sec + ru.ru_utime.tv_usec / 1e6 + ru.ru_stime.tv_sec + ru.ru_stime.tv_usec / 1e6;
			printf("BENCH copies=%d: %d units in, %d pictures out in %.1f s (%.1f fps), CPU %.2f s = %.1f %% of one core (user %.2f, system %.2f)\n",
				copies, fed, got, now() - start, got / (now() - start), cpu, cpu / (now() - start) * 100,
				ru.ru_utime.tv_sec + ru.ru_utime.tv_usec / 1e6, ru.ru_stime.tv_sec + ru.ru_stime.tv_usec / 1e6);
			return 0;
		}
		for(int i = 0; i < NOUT && pos < end; i++) {
			if(ob[i].busy) continue;
			if(bench && now() - start < fed / 60.0) break;
			const uint8_t *e = next_au(pos, end);
			size_t n = e - pos;
			if(n > ob[i].len) DIE("access unit of %zu bytes", n);
			memcpy(ob[i].map, pos, n);
			struct v4l2_plane pl = { .bytesused = n };
			struct v4l2_buffer b = { .type = OUT, .memory = V4L2_MEMORY_MMAP, .index = i, .length = 1, .m.planes = &pl };
			b.timestamp.tv_usec = fed * 16666 % 1000000; b.timestamp.tv_sec = fed / 60;
			if(xioctl(fd, VIDIOC_QBUF, &b)) DIE("QBUF output: %s", strerror(errno));
			ob[i].busy = 1; queued++; fed++; pos = e;
		}
		if(!cap_on && fed >= 2 && now() - start > 1.5) {
			printf("no source-change event after 1.5 s: setting the capture side up anyway\n");
			setup_capture(fd);
		}
		if(!bench && now() - start > 15) { printf("RESULT: timed out (%d units in, %d pictures out)\n", fed, got); return 1; }
		struct pollfd p = { fd, POLLPRI | (cap_on ? POLLIN : 0) | (queued ? POLLOUT : 0), 0 };
		if(poll(&p, 1, bench ? 2 : 200) <= 0) continue;
		if(p.revents & POLLERR && !(p.revents & (POLLPRI | POLLIN | POLLOUT))) { usleep(5000); }
		if(p.revents & POLLPRI) {
			struct v4l2_event ev;
			while(!xioctl(fd, VIDIOC_DQEVENT, &ev))
				if(ev.type == V4L2_EVENT_SOURCE_CHANGE) { printf("source change after %d unit(s)\n", fed); setup_capture(fd); }
		}
		if(p.revents & POLLOUT)
			for(;;) {
				struct v4l2_plane pl = {0};
				struct v4l2_buffer b = { .type = OUT, .memory = V4L2_MEMORY_MMAP, .length = 1, .m.planes = &pl };
				if(xioctl(fd, VIDIOC_DQBUF, &b)) break;
				ob[b.index].busy = 0; queued--;
			}
		if(p.revents & POLLIN && cap_on)
			for(;;) {
				struct v4l2_plane pl = {0};
				struct v4l2_buffer b = { .type = CAP, .memory = V4L2_MEMORY_MMAP, .length = 1, .m.planes = &pl };
				if(xioctl(fd, VIDIOC_DQBUF, &b)) break;
				if(pl.bytesused && !(b.flags & V4L2_BUF_FLAG_ERROR) && ++got == target) {
					printf("picture %d: buffer %u, %u bytes, after %.2f s\n", got, b.index, pl.bytesused, now() - start);
					return test_frame(fd, b.index, w, h, argc > 3 ? argv[3] : NULL);
				}
				if(bench && pl.bytesused) {
					uint32_t st = capfmt.fmt.pix_mp.plane_fmt[0].bytesperline, ch = capfmt.fmt.pix_mp.height;
					const uint8_t *m = cb[b.index].map;
					for(int c = 0; c < copies; c++) {
						for(uint32_t r = 0; r < h; r++) memcpy(tmp + r * w, m + r * st, w);
						for(uint32_t r = 0; r < h / 2; r++) memcpy(tmp + (size_t)w * h + r * w, m + (size_t)st * ch + r * st, w);
						__asm__ volatile("" : : "r"(tmp) : "memory");
					}
				}
				if(xioctl(fd, VIDIOC_QBUF, &b)) break; /* stream was restarted */
			}
		if(pos >= end && !queued && got < target) { usleep(300000); if(pos >= end) { printf("RESULT: stream ended with %d picture(s)\n", got); return 1; } }
	}
}
