# Device SDK in $THEOS/sdks (iPhoneOS10.3.sdk from github.com/theos/sdks), deployment target iOS 6.0
export ARCHS = armv7
export TARGET = iphone:clang:10.3:6.0
include $(THEOS)/makefiles/common.mk
SUBPROJECTS = daemon prefs app
include $(THEOS_MAKE_PATH)/aggregate.mk
