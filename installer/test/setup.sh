#!/bin/bash
# Fake tablet for installer tests.  Creates loop devices only; run as root.
# Test harness: copy this and inner.sh to a scratch directory and run there
# (it creates fake partition files next to itself).  See ../README.md.
set -euo pipefail
S=$(cd "$(dirname "$0")" && pwd)
cd $S
declare -A SZ=([boot]=100663296 [init_boot]=8388608 [vendor_boot]=100663296 [dtbo]=16777216)
declare -A NUM=([boot]=21 [init_boot]=22 [vendor_boot]=23 [dtbo]=24)
: > loops.txt
for n in boot init_boot vendor_boot dtbo; do
	[ -f android-$n.img ] || head -c ${SZ[$n]} /dev/urandom > android-$n.img
	cp android-$n.img part-$n.bin
	l=$(losetup -f --show part-$n.bin)
	echo "$n ${NUM[$n]} $l" >> loops.txt
done
SDF=${SD_FILE:-/emre/ubuntu-port/build/test-sd.bin}; rm -f $SDF; truncate -s 9G $SDF
echo "sd 0 $(losetup -fP --show $SDF)" >> loops.txt
cat loops.txt
