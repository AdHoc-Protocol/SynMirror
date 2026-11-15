# The package of SYN Mirror for the build system of OpenWrt: put this folder into package/ of the SDK and run
#   make package/syn-mirror/compile
# Scripts and rules only, the script `give` of ucode too: one package fits every architecture.

include $(TOPDIR)/rules.mk

PKG_NAME:=syn-mirror
PKG_VERSION:=0.1
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/syn-mirror
  SECTION:=net
  CATEGORY:=Network
  TITLE:=The meeting of two TCP connections in the NAT of the router
  DEPENDS:=+firewall4 +ucode +ucode-mod-socket +ucode-mod-uci +ucode-mod-math +ucode-mod-fs
  PKGARCH:=all
endef

define Package/syn-mirror/description
  Two sides, each behind its NAT, dial the same port of the router; the router sends the SYN of one to the other as if from
  itself - TCP simultaneous open - and carries their connection in the kernel, as a forwarded port. A side asks the router for a
  free port of meeting with a password of 8 bytes, and opens it by a knock: one UDP packet with the password. Rules of nftables,
  and a script of ucode that hands out the ports.
endef

define Package/syn-mirror/conffiles
/etc/config/syn-mirror
endef

define Build/Compile
endef

define Package/syn-mirror/install
	$(INSTALL_DIR) $(1)/etc/config $(1)/etc/init.d $(1)/usr/libexec/syn-mirror $(1)/usr/share/syn-mirror
	$(INSTALL_CONF) ./files/syn-mirror.config $(1)/etc/config/syn-mirror
	$(INSTALL_BIN) ./files/syn-mirror.init $(1)/etc/init.d/syn-mirror
	$(INSTALL_BIN) ./files/rules $(1)/usr/libexec/syn-mirror/rules
	$(INSTALL_BIN) ./files/uninstall $(1)/usr/libexec/syn-mirror/uninstall
	$(INSTALL_DATA) ./files/give.uc $(1)/usr/libexec/syn-mirror/give.uc
	$(INSTALL_DATA) ./files/public.uc $(1)/usr/libexec/syn-mirror/public.uc
	$(INSTALL_DATA) ./files/syn-mirror.nft $(1)/usr/share/syn-mirror/syn-mirror.nft
endef

$(eval $(call BuildPackage,syn-mirror))
