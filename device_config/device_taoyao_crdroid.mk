# lineage_taoyao.mk — unified product file for taoyao, crDroid 16.0 and EvolutionX
#
# DEPLOY: copy to  device/xiaomi/taoyao/lineage_taoyao.mk  in the ROM source tree.
#
# Both crDroid and EvolutionX use  lunch lineage_taoyao-bp4a-userdebug.
# The  inherit-product-if-exists  guard on crdroid/crdroid.mk makes this file
# safe on EvolutionX (where that file is absent).

# --- device-level config ---
$(call inherit-product, device/xiaomi/taoyao/device.mk)

# --- ROM vendor config ---
# vendor/lineage is present on both crDroid and EvolutionX under the same path.
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)

# --- crDroid overlay (absent on EvolutionX; guard prevents hard failure) ---
$(call inherit-product-if-exists, device/xiaomi/taoyao/crdroid/crdroid.mk)

# --- product identity ---
PRODUCT_BRAND           := Xiaomi
PRODUCT_DEVICE          := taoyao
PRODUCT_MANUFACTURER    := Xiaomi
PRODUCT_MODEL           := 2210129SG
PRODUCT_NAME            := lineage_taoyao

# Google Play device-check base ID for Xiaomi hardware.
# Without this line Play Store device certification fails on first boot.
PRODUCT_GMS_CLIENTID_BASE := android-xiaomi
