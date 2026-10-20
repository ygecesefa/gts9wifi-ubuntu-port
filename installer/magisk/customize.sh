# Magisk / KernelSU / APatch step of the gts9wifi Ubuntu installer zip.
#
# The Magisk app checks the zip's updater-script for #MAGISK, runs its
# update-binary (installer/update-binary.sh), which hands over to Magisk's
# install_module; that sources this file with ZIPFILE, MODPATH and TMPDIR set
# (KernelSU and APatch source it directly).  SKIPUNZIP=1: the zip is mostly
# the 1.5 GB SD image, so only the module's own files are unpacked here.
#
# 1. unpack the module (installer/magisk/module/), gts9w-tool cut out of the
#    loader exactly as update-binary.sh does, the loader itself and
#    restore.sh (both reused for android-restore.zip)
# 2. run the installer in Android mode (installer/install.sh,
#    GTS9W_MODE=android): it asks, writes the card and the Ubuntu boot
#    images; if it fails or is cancelled, abort: no module is installed
SKIPUNZIP=1

gts9w_w=$TMPDIR/gts9w-module
rm -rf $gts9w_w
mkdir -p $gts9w_w $MODPATH/bin
unzip -o "$ZIPFILE" module.prop META-INF/com/google/android/update-binary \
	gts9wifi/SHA256SUMS gts9wifi/install.sh gts9wifi/restore.sh gts9wifi/version.txt \
	'module/*' -d $gts9w_w >&2 || abort "! Could not unpack the zip"
for gts9w_f in install.sh restore.sh; do
	[ "$(sha256sum $gts9w_w/gts9wifi/$gts9w_f | cut -d' ' -f1)" = \
		"$(grep " $gts9w_f\$" $gts9w_w/gts9wifi/SHA256SUMS | cut -d' ' -f1)" ] ||
		abort "! sha256 mismatch: $gts9w_f"
done

gts9w_ub=$gts9w_w/META-INF/com/google/android/update-binary
gts9w_total=$(stat -c %s $gts9w_ub)
gts9w_off=$(tail -c 16 $gts9w_ub | sed 's/^0*//')
tail -c +$((${gts9w_off:-0} + 1)) $gts9w_ub | head -c $((gts9w_total - 16 - ${gts9w_off:-0})) > $MODPATH/bin/gts9w-tool
chmod 0755 $MODPATH/bin/gts9w-tool
$MODPATH/bin/gts9w-tool >/dev/null 2>&1
[ $? = 2 ] || abort "! gts9w-tool does not run here"
cp $gts9w_ub $MODPATH/update-binary
cp $gts9w_w/gts9wifi/restore.sh $gts9w_w/gts9wifi/version.txt $gts9w_w/module.prop $MODPATH/
cp -r $gts9w_w/module/. $MODPATH/

GTS9W_MODE=android GTS9W_TOOL=$MODPATH/bin/gts9w-tool GTS9W_LOADER=$MODPATH/update-binary \
	sh $gts9w_w/gts9wifi/install.sh 0 1 "$ZIPFILE" ||
	abort "! Not installed (the Magisk module neither)."
rm -rf $gts9w_w

set_perm_recursive $MODPATH 0 0 0755 0644
for gts9w_f in bin/gts9w-tool gts9w.sh to-ubuntu.sh service.sh action.sh; do
	set_perm $MODPATH/$gts9w_f 0 0 0755
done
ui_print "- Module installed: Ubuntu switch (action button / WebUI)."
