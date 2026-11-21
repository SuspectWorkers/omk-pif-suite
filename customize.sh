#!/system/bin/sh
ui_print "- Installing OMK PIF Suite (v1.3.1)"
set_perm_recursive "$MODPATH/webroot" 0 0 0755 0644
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/common.sh" 0 0 0644
