LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
MRUBY_PATH = ../../../mruby
LOCAL_MODULE    := mruby-prebuilt
LOCAL_SRC_FILES := $(MRUBY_PATH)/build/androideabi/lib/libmruby.a
LOCAL_EXPORT_C_INCLUDES := $(LOCAL_PATH)/$(MRUBY_PATH)/include
LOCAL_STATIC_LIBRARIES += android_support

include $(PREBUILT_STATIC_LIBRARY)
$(call import-module,android/support)
