include $(THEOS)/makefiles/common.mk
APPLICATION_NAME = TuneFetch
TuneFetch_FILES = main.m TFCommon.m TFAppDelegate.m TFDownloadsVC.m TFSettingsVC.m TFScanVC.m tf_divmod.c quirc/decode.c quirc/identify.c quirc/quirc.c quirc/version_db.c
TuneFetch_FRAMEWORKS = UIKit Foundation CoreGraphics QuartzCore AVFoundation CoreMedia CoreVideo
TuneFetch_CFLAGS = -fobjc-arc -Iquirc
# the SDK's armv7 stubs lack objc_msgSend_stret (struct returns such as CGRect); the phone's libobjc has it
TuneFetch_LDFLAGS = -Wl,-U,_objc_msgSend_stret
include $(THEOS_MAKE_PATH)/application.mk
