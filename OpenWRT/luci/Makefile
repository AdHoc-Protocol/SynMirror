# The page of SYN Mirror in LuCI, for the build system of OpenWrt: put this folder into the LuCI feed as applications/luci-app-syn-mirror
# and run
#   make package/luci-app-syn-mirror/compile

include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI page of SYN Mirror: the password, the settings, the connections
LUCI_DEPENDS:=+luci-base +syn-mirror
LUCI_PKGARCH:=all

PKG_NAME:=luci-app-syn-mirror
PKG_VERSION:=0.1
PKG_RELEASE:=1

include ../../luci.mk

# call BuildPackage - OpenWrt buildroot signature
