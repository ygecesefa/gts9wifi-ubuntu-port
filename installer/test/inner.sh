#!/bin/bash
# Runs inside `unshare -m`: builds /dev/block, /sys/block/mmcblk1, /dev/input
# and getprop as a recovery would show them, then runs one update-binary.
#   inner.sh UPDATE_BINARY ZIP ANSWERS   (ANSWERS: y/n per question, e.g. "y")
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
printf '#!/bin/sh\ncase "$1" in ro.product.device|ro.build.product) echo gts9wifi;; ro.build.fingerprint) echo test/fake;; esac\n' > $S/bin/getprop
chmod +x $S/bin/getprop
: > $S/outfd.log
# Answer each "Volume Up" question in turn.
(
	asked=0
	for a in $(echo $answers | sed 's/./& /g'); do
		while [ "$(grep -c 'Volume Up' $S/outfd.log)" -le $asked ]; do sleep 0.3; done
		asked=$((asked + 1)); sleep 1.5
		code=115; [ $a = n ] && code=114
		python3 -c "import struct,sys; sys.stdout.buffer.write(struct.pack('qqHHi',0,0,1,$code,1)+struct.pack('qqHHi',0,0,1,$code,0))" > /dev/input/event0
	done
) &
feeder=$!
cp "$ub" /tmp/update-binary-test
set +e
PATH=$S/bin:$PATH ${TEST_SH:-sh} /tmp/update-binary-test 3 3 "$zip" 3>>$S/outfd.log
rc=$?
kill $feeder 2>/dev/null
sed -n 's/^ui_print //p' $S/outfd.log | grep -v '^$'
echo "RC=$rc"
