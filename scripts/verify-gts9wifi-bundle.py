#!/usr/bin/env python3
"""Statically verify a gts9wifi boot bundle before it goes near the tablet.

Checks boot.img (ANDROID! v4, kernel == Image.gz + DTB, empty cmdline),
init_boot.img (v4, empty LZ4-legacy ramdisk), vendor_boot.img (VNDRBOOT v4,
DTB == the built DTB, cmdline with the GTS9W_ROOT root, LZ4-legacy initramfs
containing init, the kernel modules and the GPU firmware) and dtbo.img (zero
page), plus the partition sizes.  Never writes anything.

usage: verify-gts9wifi-bundle.py BUNDLE_DIR KERNEL_OUT_DIR
"""
import pathlib
import struct
import subprocess
import sys

SIZES = {'boot.img': 100663296, 'init_boot.img': 8388608,
         'vendor_boot.img': 100663296, 'dtbo.img': 16777216}
LZ4_LEGACY = b'\x02\x21\x4c\x18'
failures = []


def check(ok, what):
    print(('  ok   ' if ok else '  FAIL ') + what)
    if not ok:
        failures.append(what)


def align(n, page):
    return (n + page - 1) // page * page


def cpio_names(raw):
    names, off = set(), 0
    while raw[off:off + 6] == b'070701':
        namesize = int(raw[off + 94:off + 102], 16)
        filesize = int(raw[off + 54:off + 62], 16)
        name = raw[off + 110:off + 110 + namesize - 1].decode(errors='replace')
        off = align(off + 110 + namesize, 4)
        off = align(off + filesize, 4)
        if name != 'TRAILER!!!':
            names.add(name.lstrip('./'))
        while off < len(raw) and raw[off:off + 6] != b'070701':
            off += 1
    return names


def main(bundle, kout):
    bundle, kout = pathlib.Path(bundle), pathlib.Path(kout)
    kernel = (kout / 'Image.gz').read_bytes()
    dtb = (kout / 'sm8550-samsung-gts9wifi.dtb').read_bytes()
    krel = (kout / 'kernel.release').read_text().strip()

    print('sizes')
    for name, size in SIZES.items():
        check((bundle / name).stat().st_size == size, f'{name} is {size} bytes')
    check(not (bundle / 'vbmeta.img').exists(), 'no vbmeta.img in the bundle')

    print('boot.img')
    b = (bundle / 'boot.img').read_bytes()
    ksize, rsize = struct.unpack_from('<II', b, 8)
    hver = struct.unpack_from('<I', b, 40)[0]
    check(b[:8] == b'ANDROID!' and hver == 4, 'ANDROID! header v4')
    check(b[4096:4096 + ksize] == kernel + dtb, 'kernel payload == Image.gz + gts9wifi DTB')
    check(rsize == 0, 'no ramdisk in boot.img')
    check(b[44:44 + 1536].rstrip(b'\0') == b'', 'empty boot cmdline (ABL forbids one here)')

    print('init_boot.img')
    i = (bundle / 'init_boot.img').read_bytes()
    _, rsize = struct.unpack_from('<II', i, 8)
    rd = i[4096:4096 + rsize]
    check(i[:8] == b'ANDROID!' and rd[:4] == LZ4_LEGACY, 'v4 header, LZ4-legacy ramdisk')
    raw = subprocess.run(['lz4', '-dc'], input=rd, stdout=subprocess.PIPE, check=True).stdout
    check(cpio_names(raw) <= {'', '.'}, 'generic ramdisk is empty')

    print('vendor_boot.img')
    v = (bundle / 'vendor_boot.img').read_bytes()
    check(v[:8] == b'VNDRBOOT', 'VNDRBOOT magic')
    hver, page = struct.unpack_from('<II', v, 8)
    vr_size = struct.unpack_from('<I', v, 24)[0]
    cmdline = v[28:28 + 2048].rstrip(b'\0').decode()
    hdr_size, dtb_size = struct.unpack_from('<II', v, 2096)
    check(hver == 4 and page == 4096, 'header v4, page 4096')
    check('root=LABEL=GTS9W_ROOT' in cmdline, 'cmdline mounts root=LABEL=GTS9W_ROOT')
    check('msm_drm.dsi_display0=GTS9_ANA38407_AMSA10FA01' in cmdline, 'cmdline selects the X710 panel')
    vr_off = align(hdr_size, page)
    dtb_off = vr_off + align(vr_size, page)
    check(v[dtb_off:dtb_off + dtb_size] == dtb, 'vendor_boot DTB == built gts9wifi DTB')
    ramdisk = v[vr_off:vr_off + vr_size]
    check(ramdisk[:4] == LZ4_LEGACY, 'vendor ramdisk is LZ4 legacy')
    raw = subprocess.run(['lz4', '-dc'], input=ramdisk, stdout=subprocess.PIPE, check=True).stdout
    names = cpio_names(raw)
    check('init' in names, 'initramfs has /init')
    check(any(n.startswith(f'usr/lib/modules/{krel}/') or n.startswith(f'lib/modules/{krel}/')
              for n in names), f'initramfs has modules for {krel}')
    for fw in ('a740_sqe.fw', 'gmu_gen70200.bin', 'a740_zap.mdt'):
        check(any(n.endswith('firmware/qcom/' + fw) for n in names), f'initramfs has GPU firmware {fw}')

    print('dtbo.img')
    d = (bundle / 'dtbo.img').read_bytes()
    check(d[:4096] == b'\0' * 4096, 'first page is zero (not a DT table)')

    if failures:
        print(f'\n{len(failures)} check(s) failed')
        return 1
    print('\nbundle OK')
    return 0


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    sys.exit(main(*sys.argv[1:]))
