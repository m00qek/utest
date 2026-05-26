include $(TOPDIR)/rules.mk

PKG_NAME:=ucode-utest
PKG_VERSION:=0.9.0
PKG_RELEASE:=1

PKG_MAINTAINER:=António Mora <oliveira.fh42@gmail.com>
PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE

include $(INCLUDE_DIR)/package.mk

define Package/ucode-utest
  SECTION:=devel
  CATEGORY:=Development
  TITLE:=Unit testing framework for ucode
  URL:=https://github.com/m00qek/utest
  DEPENDS:=+ucode
  PKGARCH:=all
endef

define Package/ucode-utest/description
  A modern, non-invasive testing framework for the ucode ecosystem.
  Provides a describe/it DSL, built-in mock proxies for uci, ubus, fs,
  uloop, and uclient, and both sequential and parallel test runners.
endef

define Build/Compile
endef

define Package/ucode-utest/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./src/utest.sh $(1)/usr/bin/utest

	$(INSTALL_DIR) $(1)/usr/share/ucode
	$(CP) ./src/utest.uc $(1)/usr/share/ucode/
	$(CP) -r ./src/utest $(1)/usr/share/ucode/
endef

$(eval $(call BuildPackage,ucode-utest))
