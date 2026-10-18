// SPDX-License-Identifier: MIT
//
// LD_PRELOAD shim for the four libvmmem calls Samsung's libspcom makes.
//
// libspcom allocates its NVM buffers from the qcom,sp-hlos DMA-BUF heap and
// then calls ShareDmabuf() to give the SPSS VM access through Qualcomm's
// downstream mem_buf driver (/dev/membuf).  Mainline has no mem_buf; the
// port's qcom_sp_hlos_heap performs that same SCM ownership transition when
// the buffer is allocated, for the buffer's whole lifetime.  So the share is
// already done and these calls only have to succeed; without the shim
// CreateVmMem() fails on the missing /dev/membuf and sec_nvm cannot create
// any NVM segment ("ION allocation failure").
#define EXPORT __attribute__((visibility("default")))

static int handle;

EXPORT void *CreateVmMem(void)
{
	return &handle;
}

EXPORT void FreeVmMem(void *vm)
{
	(void)vm;
}

/* Distinct, non-negative ids; libspcom only passes them back to ShareDmabuf. */
EXPORT int FindVmByName(void *vm, const char *name)
{
	(void)vm;
	return name && name[0] == 's' ? 2 : 1;
}

EXPORT int ShareDmabuf(void *vm, int fd, const int *vmids, const int *perms,
		       int count)
{
	(void)vm; (void)fd; (void)vmids; (void)perms; (void)count;
	return 0;
}
