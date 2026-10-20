#!/bin/bash
# Runs inside `unshare -m`: builds /dev/block, /sys/block/mmcblk1, /dev/input
# and getprop as a recovery would show them, then runs one update-binary.
#   inner.sh UPDATE_BINARY ZIP ANSWERS   (ANSWERS: y/n per question, e.g. "y")
# TEST_MODE=magisk: a running Android instead: ./data (kept between runs) as
# /data with a stand-in Magisk (magisk-util_functions.sh), a fingerprint
# calibration, and fake sm / blkid / reboot; the update-binary runs with
# BOOTMODE=true like the Magisk app runs it.  TEST_AFTER=script: sourced at
# the end, in the same namespace (to run the module's scripts).
set -euo pipefail
S=$(cd "$(dirname "$0")" && pwd)
ub=$1 zip=$2 answers=$3
mount --make-rprivate /
mount -t tmpfs none /dev/block
mkdir /dev/block/by-name
while read n num l; do
	if [ $n = sd ]; then
		sd=$l
		ln -s $l /dev/block/mmcblk1
		for i in 1 2 3; do ln -s ${l}p$i /dev/block/mmcblk1p$i; done
	else
		mknod /dev/block/sda$num b $(stat -c '%t %T' $l | while read a b; do echo $((16#$a)) $((16#$b)); done)
		ln -s /dev/block/sda$num /dev/block/by-name/$n
	fi
done < $S/loops.txt
mount -t tmpfs none /sys/block
mkdir -p /sys/block/mmcblk1/device; echo SD > /sys/block/mmcblk1/device/type
mount -t tmpfs none /dev/input
mkfifo /dev/input/event0
mkdir -p $S/bin
printf '#!/bin/sh\ncase "$1" in ro.product.device|ro.build.product) echo gts9wifi;; ro.build.fingerprint) cat %s/fingerprint.prop 2>/dev/null || echo test/fake;; sys.boot_completed) echo 1;; esac\n' $S > $S/bin/getprop
printf '#!/bin/sh\nfor p in /dev/block/mmcblk1p*; do l=$(/usr/sbin/blkid -p -s LABEL -o value "$(readlink -f $p)"); [ -n "$l" ] && echo "$p: LABEL=\\"$l\\""; done\n' > $S/bin/blkid
printf '#!/bin/sh\necho "sm $*" >> %s/sm.log\n' $S > $S/bin/sm
printf '#!/bin/sh\necho REBOOT >> %s/reboot.log\n' $S > $S/bin/reboot
chmod +x $S/bin/getprop $S/bin/blkid $S/bin/sm $S/bin/reboot
if [ "${TEST_MODE:-recovery}" = magisk ]; then
	mkdir -p $S/data
	mount --bind $S/data /data
	mkdir -p /data/local/tmp /data/adb/magisk /data/adb/modules_update /data/vendor/biometrics/meta
	cp $S/magisk-util_functions.sh /data/adb/magisk/util_functions.sh
	for f in calib.dat egoptbds.dat; do
		[ -f /data/vendor/biometrics/meta/$f ] || head -c 8192 /dev/urandom > /data/vendor/biometrics/meta/$f
	done
fi
: > $S/outfd.log
# Answer each question in turn.  Recovery: Volume Up (y) / Down (n).
# TEST_MODE=magisk: presses of one key, as Android swaps them on rotation:
# two (y) / one (n), sent as the swapped key a landscape tablet sends.
(
	asked=0
	press() {
		python3 -c "import struct,sys; sys.stdout.buffer.write(struct.pack('qqHHi',0,0,1,$1,1)+struct.pack('qqHHi',0,0,1,$1,0))" > /dev/input/event0
	}
	for a in $(echo $answers | sed 's/./& /g'); do
		while [ "$(grep -c 'Volume Up\|volume key TWICE' $S/outfd.log)" -le $asked ]; do sleep 0.3; done
		asked=$((asked + 1)); sleep 1.5
		if [ "${TEST_MODE:-recovery}" = magisk ]; then
			press 115
			if [ $a = y ]; then sleep 0.5; press 115; fi
			sleep 2
		else
			code=115; [ $a = n ] && code=114
			press $code
		fi
	done
) &
feeder=$!
cp "$ub" /tmp/update-binary-test
set +e

if [ "${TEST_MODE:-recovery}" = magisk ]; then
	BOOTMODE=true PATH=$S/bin:$PATH ${TEST_SH:-sh} /tmp/update-binary-test dummy 1 "$zip" >>$S/outfd.log 2>&1
	rc=$?
	kill $feeder 2>/dev/null
	grep -v '^ui_print$' $S/outfd.log
else
	PATH=$S/bin:$PATH ${TEST_SH:-sh} /tmp/update-binary-test 3 3 "$zip" 3>>$S/outfd.log
	rc=$?
	kill $feeder 2>/dev/null
	sed -n 's/^ui_print //p' $S/outfd.log | grep -v '^$'
fi
echo "RC=$rc"
if [ -n "${TEST_AFTER:-}" ]; then
	PATH=$S/bin:$PATH . "$TEST_AFTER"
fi
