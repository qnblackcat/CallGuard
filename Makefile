TARGET = iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = callservicesd MobilePhone Preferences

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CallGuard

CallGuard_FILES = Tweak.x TweakPhone.x CGPolicy.m CGShared.m CGLog.m
CallGuard_FRAMEWORKS = UserNotifications
CallGuard_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
