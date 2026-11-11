# crdroid.mk — crDroid 16.0 overlay for Xiaomi 12 Lite (taoyao, SM7325 / Adreno 642L)
#
# DEPLOY: copy to  device/xiaomi/taoyao/crdroid/crdroid.mk  in the ROM source tree.
#
# Included by lineage_taoyao.mk via  inherit-product-if-exists.
# When this file is absent (EvolutionX checkout), nothing below runs — safe to leave
# the guard in lineage_taoyao.mk unconditionally.

# Adreno 642L cannot sustain the Gaussian blur shader at 120 Hz without visible jank.
# Disabling here; EvolutionX may set its own value via vendor/evolution.
TARGET_SUPPORTS_BLUR := false

# No face-unlock blob in vendor/xiaomi/taoyao (lineage-23.2 base):
# disabling prevents crDroidSettings from showing a non-functional option.
TARGET_FACE_UNLOCK_SUPPORTED := false

# Google Quick Tap requires a Pixel-specific sensor HAL not present on SM7325.
TARGET_SUPPORTS_QUICK_TAP := false

# MatLog (crDroid in-ROM bug-report shortcut) — keep enabled.
TARGET_DISABLE_MATLOG := false

# crDroid overlay directory: display cutout overrides, rounded corners, status bar.
# Provides frameworks/base/core/res and frameworks/base/packages/SystemUI overrides.
DEVICE_PACKAGE_OVERLAYS += device/xiaomi/taoyao/crdroid/overlay


# ---------------------------------------------------------------------------
# AndroidProducts.mk entry — also lives here as a convenience reference.
# DEPLOY: device/xiaomi/taoyao/AndroidProducts.mk must list lineage_taoyao.mk.
# ---------------------------------------------------------------------------
#
# PRODUCT_MAKEFILES := \
#     $(LOCAL_DIR)/lineage_taoyao.mk
#
# COMMON_LUNCH_CHOICES := \
#     lineage_taoyao-bp4a-userdebug \
#     lineage_taoyao-bp4a-user
