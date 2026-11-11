#!/usr/bin/env bash
# Build the MeruLink kernel for crDroid 16.0 (taoyao) and produce a flashable boot.img.
#
# Wrapper around ROM_BUILD/kernel/build/build_kernel.sh; runs the source, config,
# build and package stages with the crDroid-specific switches, then repackages the
# resulting Image into a crDroid boot.img via magiskboot.
#
# Run from Windows (the script itself is run inside WSL):
#   wsl -d Ubuntu-24.04 -u root -- bash /mnt/d/MeruDevTools/ROM_BUILD/crdroid/build_crdroid_kernel.sh [all|build|boot]
#
# Stages:
#   all    source + config + build + package + boot  (default)
#   build  source + config + build + package only (no boot.img)
#   boot   repack boot.img from an already-built Image (fast; needs the Image from a prior run)
#
# Settings (environment):
#   WORK           WSL work directory for the kernel tree  (default $HOME/taoyao-kernel-crdroid)
#   CRDROID_BOOT   path (WSL) to the reference crDroid boot.img to unpack/repack
#                  default: /mnt/d/MeruDevTools/ROM_BUILD/kernel/crdroid_files/boot.img
#   MAGISKBOOT     path (WSL) to magiskboot binary         (default: magiskboot from PATH or tools/)
#   OUT_WIN        Windows output directory (WSL path)
#                  default: /mnt/d/MeruDevTools/ROM_BUILD/crdroid/out
#
# The kernel is always built with:
#   WITH_KSU=1  WITH_USB_CHANNEL=1  WITH_XHID_STEALTH=1  TOOLCHAIN=llvm-apt
#
# Extra settings:
#   USE_PREBUILT    1 = skip the build, take the already-built Image from OUT_WIN/kernel/
#                   0 = build from source (default)
#   PREBUILT_DST    WSL path to device/xiaomi/taoyao/prebuilt/ inside the crDroid tree
#                   default: $HOME/crdroid/device/xiaomi/taoyao/prebuilt
#                   Set to empty to skip the copy step.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BUILD_SH=/mnt/d/MeruDevTools/ROM_BUILD/kernel/build/build_kernel.sh

WORK=${WORK:-$HOME/taoyao-kernel-crdroid}
OUT_WIN=${OUT_WIN:-/mnt/d/MeruDevTools/ROM_BUILD/crdroid/out}
CRDROID_BOOT=${CRDROID_BOOT:-/mnt/d/MeruDevTools/ROM_BUILD/kernel/crdroid_files/boot.img}
MAGISKBOOT=${MAGISKBOOT:-}
USE_PREBUILT=${USE_PREBUILT:-0}
PREBUILT_DST=${PREBUILT_DST:-$HOME/crdroid/device/xiaomi/taoyao/prebuilt}

WIN_KERNEL=/mnt/d/MeruDevTools/ROM_BUILD/kernel

log() { printf '\n== %s  [%s]\n' "$*" "$(date '+%F %T')"; }
die() { echo "ERROR: $*" >&2; exit 1; }

# --- kernel build switches for crDroid MeruLink build ---
export WITH_KSU=1
export WITH_USB_CHANNEL=1
export WITH_XHID_STEALTH=1
export WITH_BATTERY_FIX=0
export TOOLCHAIN=llvm-apt
export WORK
export WIN=$WIN_KERNEL
export ROM_TARGET=crdroid
# output goes to its own dir so it does not overwrite evox artifacts
export OUT_DIR_WIN=$OUT_WIN/kernel

find_magiskboot() {
    if [ -n "$MAGISKBOOT" ] && [ -x "$MAGISKBOOT" ]; then
        echo "$MAGISKBOOT"; return
    fi
    local mb
    mb=$(command -v magiskboot 2>/dev/null || true)
    if [ -n "$mb" ]; then echo "$mb"; return; fi
    # common locations in Magisk releases
    for try in \
        /mnt/d/MeruDevTools/ROM_BUILD/kernel/tools/magiskboot \
        /usr/local/bin/magiskboot \
        "$HOME/bin/magiskboot"; do
        [ -x "$try" ] && { echo "$try"; return; }
    done
    echo ""
}

stage_build() {
    if [ "$USE_PREBUILT" = "1" ]; then
        log "USE_PREBUILT=1: skipping kernel compilation, using existing Image from $OUT_WIN/kernel/"
        local image
        image=$(ls -t "$OUT_WIN"/kernel/Image-ksu* 2>/dev/null | head -1 || true)
        [ -f "$image" ] || die "USE_PREBUILT=1 but no Image-ksu* found in $OUT_WIN/kernel/. Run without USE_PREBUILT first."
        log "prebuilt Image: $image"
        return 0
    fi
    log "kernel build (crDroid — MeruLink: KSU + USB channel + XHID stealth)"
    [ -f "$BUILD_SH" ] || die "kernel build script not found: $BUILD_SH"
    # run source, config, build, package
    bash "$BUILD_SH" source
    bash "$BUILD_SH" config
    bash "$BUILD_SH" build
    bash "$BUILD_SH" package
    log "kernel build done"
}

# Copy the built Image into the device tree's prebuilt directory so the crDroid
# ROM build can consume it as TARGET_PREBUILT_KERNEL instead of building its own.
stage_copy_prebuilt() {
    [ -n "$PREBUILT_DST" ] || { log "PREBUILT_DST is empty, skipping copy to device tree"; return 0; }
    log "copy Image -> $PREBUILT_DST"

    local image
    if [ "$USE_PREBUILT" = "1" ]; then
        image=$(ls -t "$OUT_WIN"/kernel/Image-ksu* 2>/dev/null | head -1 || true)
    else
        local tag=ksu
        [ "$WITH_USB_CHANNEL" = 1 ] && tag=${tag}-xhid
        local kref
        kref=$(git -C "$WORK/src" rev-parse HEAD 2>/dev/null | cut -c1-7 || echo "unknown")
        image=$OUT_WIN/kernel/Image-${tag}-${kref}-${TOOLCHAIN}
        [ -f "$image" ] || image=$(ls -t "$OUT_WIN"/kernel/Image-ksu* 2>/dev/null | head -1 || true)
    fi
    [ -f "$image" ] || die "kernel Image not found in $OUT_WIN/kernel/. Run the build stage first."

    mkdir -p "$PREBUILT_DST"
    cp "$image" "$PREBUILT_DST/Image"
    # Many device trees also want Image.gz; create it alongside
    if command -v gzip > /dev/null 2>&1; then
        gzip -9 -k -f "$image"
        local imgz=${image}.gz
        [ -f "$imgz" ] && cp "$imgz" "$PREBUILT_DST/Image.gz" || true
    fi
    log "Image copied to $PREBUILT_DST/Image"
    ls -lh "$PREBUILT_DST"/Image*
}

stage_boot() {
    log "boot.img assembly (magiskboot)"

    local mb
    mb=$(find_magiskboot)
    [ -n "$mb" ] || die "magiskboot not found. Put it in /mnt/d/MeruDevTools/ROM_BUILD/kernel/tools/magiskboot or add it to PATH."

    [ -f "$CRDROID_BOOT" ] || die "reference crDroid boot.img not found: $CRDROID_BOOT\n  Build crDroid once to get it, or copy from an existing crDroid zip."

    # Determine the VARIANT tag that build_kernel.sh computed (matches OUT_DIR_WIN naming)
    local tag=ksu
    [ "$WITH_USB_CHANNEL" = 1 ] && tag=${tag}-xhid
    local kref
    kref=$(git -C "$WORK/src" rev-parse HEAD 2>/dev/null | cut -c1-7 || echo "unknown")
    local variant=${tag}-${kref}-${TOOLCHAIN}
    local image=$OUT_WIN/kernel/Image-$variant

    if [ ! -f "$image" ]; then
        # fallback: any Image-ksu* in the out dir (most recent)
        image=$(ls -t "$OUT_WIN"/kernel/Image-ksu* 2>/dev/null | head -1 || true)
        [ -f "$image" ] || die "kernel Image not found in $OUT_WIN/kernel/. Run the build stage first."
        log "using Image: $image (variant fallback)"
    else
        log "using Image: $image"
    fi

    local workdir=$OUT_WIN/boot_work
    rm -rf "$workdir"
    mkdir -p "$workdir"

    # Unpack the reference crDroid boot.img
    cp "$CRDROID_BOOT" "$workdir/boot.img"
    cd "$workdir"
    "$mb" unpack boot.img

    # Replace the kernel
    cp "$image" "$workdir/kernel"

    # Repack
    "$mb" repack boot.img "$workdir/new-boot.img"

    mkdir -p "$OUT_WIN"
    cp "$workdir/new-boot.img" "$OUT_WIN/boot-crdroid-merulink.img"
    local sz
    sz=$(stat -c %s "$OUT_WIN/boot-crdroid-merulink.img")
    log "boot.img ready: $OUT_WIN/boot-crdroid-merulink.img  ($sz bytes)"
    ls -lh "$OUT_WIN/boot-crdroid-merulink.img"
}

case ${1:-all} in
    all)
        stage_build
        stage_copy_prebuilt
        stage_boot
        ;;
    build)
        stage_build
        stage_copy_prebuilt
        ;;
    boot)
        stage_boot
        ;;
    prebuilt)
        stage_copy_prebuilt
        ;;
    *)
        sed -n '2,30p' "$0"
        exit 1
        ;;
esac
