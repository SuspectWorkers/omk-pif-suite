#!/system/bin/sh
ui_print "- Installing OMK PIF Suite (v1.8.1)"
set_perm_recursive "$MODPATH/webroot" 0 0 0755 0644
[ -d "$MODPATH/probe" ] && set_perm_recursive "$MODPATH/probe" 0 0 0755 0644
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
set_perm "$MODPATH/common.sh" 0 0 0644
