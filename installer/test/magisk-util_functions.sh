# Stand-in for Magisk's /data/adb/magisk/util_functions.sh in the installer
# tests (inner.sh, TEST_MODE=magisk): just the parts of install_module the
# gts9wifi zip relies on, in Magisk's order (module.prop, customize.sh,
# SKIPUNZIP, source it, drop it).  The real one is tested on the tablet.
MAGISK_VER_CODE=28000
TMPDIR=/data/magisk-tmp
grep_prop() { sed -n "s/^$1=//p" "$2" | head -n 1; }
abort() { ui_print "$1"; rm -rf "$MODPATH" "$TMPDIR"; exit 1; }
set_perm() { chown "$2:$3" "$1"; chmod "$4" "$1"; }
set_perm_recursive() {
	find "$1" -type d -exec chown "$2:$3" {} + -exec chmod "$4" {} +
	find "$1" -type f -exec chown "$2:$3" {} + -exec chmod "$5" {} +
}
install_module() {
	rm -rf $TMPDIR
	mkdir -p $TMPDIR
	cd $TMPDIR
	unzip -o "$ZIPFILE" module.prop -d $TMPDIR >&2
	[ -f $TMPDIR/module.prop ] || abort "! Unable to extract zip file!"
	MODID=$(grep_prop id $TMPDIR/module.prop)
	MODPATH=/data/adb/modules_update/$MODID
	rm -rf $MODPATH
	mkdir -p $MODPATH
	ui_print "- $(grep_prop name $TMPDIR/module.prop)"
	unzip -o "$ZIPFILE" customize.sh -d $MODPATH >&2
	grep -q '^SKIPUNZIP=1$' $MODPATH/customize.sh || abort "! test expects SKIPUNZIP=1"
	. $MODPATH/customize.sh
	rm -f $MODPATH/customize.sh
	cd /
	rm -rf $TMPDIR
	ui_print "- Done"
}
