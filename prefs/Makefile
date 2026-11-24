TARGET = iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
CG_VERSION := $(shell awk '/^Version:/ {print $$2}' ../control)

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CallGuardPrefs

CallGuardPrefs_FILES = CGRootListController.m ../CGShared.m ../CGLog.m
CallGuardPrefs_INSTALL_PATH = /Library/PreferenceBundles
CallGuardPrefs_FRAMEWORKS = UIKit
CallGuardPrefs_PRIVATE_FRAMEWORKS = Preferences
CallGuardPrefs_CFLAGS = -fobjc-arc -DCG_VERSION=\"$(CG_VERSION)\"

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/CallGuardPrefs.plist$(ECHO_END)
