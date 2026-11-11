#!/usr/bin/env bash
# Builds crDroid 16.0 for the Xiaomi 12 Lite (taoyao) on a Linux server, stage by stage.
#
# Run it as the unprivileged user "build" (server_setup.sh makes it), inside tmux, from the kit directory:
#   KERNEL_BUNDLE=$HOME/Mi-12-lite-kernel-all-branches.bundle ./build_crdroid.sh all
#
# Stages (each can be run alone and again; a finished stage costs almost nothing the second time):
#   check      the tools this script needs are there (it needs no root)
#   init       repo init for crDroid + the local manifest taoyao.xml
#   sync       repo sync (1-3 hours; retries; Git LFS for the firmware and camera repositories)
#   kernel     your kernel repository into kernel/xiaomi/taoyao (from a bundle file or a URL)
#   firmware   the 17 firmware images must be real files, not Git LFS pointers
#   preflight  cheap checks before the expensive step
#   smoke      breakfast taoyao + m nothing: the manifest, the device tree and Soong's analysis
#   build      m bacon: the OTA zip
#   collect    the zip, boot/vendor_boot/dtbo images and the pinned manifest into $WORK/artifacts
#   all        every stage above, in order
#
# Settings (environment):
#   KERNEL_BUNDLE   a git bundle with your kernel repository (preferred: nothing to log in to)
#   KERNEL_URL      or a URL it can be cloned from (a private repository needs a token in the URL)
#   KERNEL_BRANCH   branch to build              (default taoyao-5.4.302; ...-hardened has the small fixes)
#   KSU             1 = taoyao_defconfig becomes taoyao_suki_defconfig (SukiSU-Ultra), 0 = the ROM kernel as it is
#   FIRMWARE_DIR    folder with the 17 *.img, used when Git LFS cannot deliver them
#   WORK            where the tree lives         (default $HOME/crdroid)
#   VARIANT         userdebug (default) or user
#   CRDROID_BRANCH  16.0 (default)
#   DEPTH           1 = shallow clones (default, saves ~100 GB and time); empty = full history
#   SYNC_JOBS       parallel fetches             (default 8)
set -eo pipefail

KIT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORK=${WORK:-$HOME/crdroid}
CRDROID_BRANCH=${CRDROID_BRANCH:-16.0}
VARIANT=${VARIANT:-userdebug}
KERNEL_BRANCH=${KERNEL_BRANCH:-taoyao-5.4.302}
KERNEL_BUNDLE=${KERNEL_BUNDLE:-}
KERNEL_URL=${KERNEL_URL:-}
KSU=${KSU:-1}
FIRMWARE_DIR=${FIRMWARE_DIR:-}
DEPTH=${DEPTH-1}
SYNC_JOBS=${SYNC_JOBS:-8}
LOG=$WORK/logs
KDIR=kernel/xiaomi/taoyao
FWDIR=vendor/xiaomi/taoyao-firmware

log() { printf '\n== %s  [%s]\n' "$*" "$(date '+%F %T')"; }
die() { echo "ERROR: $*" >&2; exit 1; }

retry() {   # retry <times> <command...>
    local n=$1 i
    shift
    for i in $(seq 1 "$n"); do
        "$@" && return 0
        echo "attempt $i/$n failed: $*" >&2
        sleep 20
    done
    return 1
}

stage_check() {
    log "tools on this machine (nothing here needs root)"
    local miss=0 t
    for t in repo git python3 curl rsync zip unzip; do
        if command -v "$t" > /dev/null 2>&1; then echo "ok   $t"; else echo "MISSING $t"; miss=1; fi
    done
    if git lfs version > /dev/null 2>&1; then echo "ok   git lfs"; else echo "MISSING git lfs"; miss=1; fi
    if command -v ccache > /dev/null 2>&1; then echo "ok   ccache"; else echo "note ccache is missing (optional)"; fi
    echo "RAM $(awk '/MemTotal/ {printf "%d", $2/1048576}' /proc/meminfo) GB, CPUs $(nproc --all), free under \$HOME: $(df -BG --output=avail "$HOME" | tail -1 | tr -d ' ')"
    git config --global user.name > /dev/null || { echo "git identity is not set: git config --global user.name/user.email"; miss=1; }
    [ "$miss" = 0 ] || die "something is missing: install it, or ask the provider's admin to (a shared server without root: 'please apt install <package>')"
}

stage_init() {
    log "repo init (crDroid $CRDROID_BRANCH)"
    mkdir -p "$WORK" "$LOG"
    cd "$WORK"
    if [ ! -d .repo ]; then
        retry 3 repo init -u https://github.com/crdroidandroid/android.git -b "$CRDROID_BRANCH" \
            --git-lfs --no-clone-bundle ${DEPTH:+--depth="$DEPTH"}
    fi
    mkdir -p .repo/local_manifests
    cp "$KIT/taoyao.xml" .repo/local_manifests/taoyao.xml
    repo manifest | grep -c 'xiaomi' | xargs echo "projects with xiaomi in the merged manifest:"
}

sync_once() {
    cd "$WORK"
    repo sync -c --no-tags --no-clone-bundle --optimized-fetch --force-sync -j"$SYNC_JOBS" 2>&1 | tee -a "$LOG/sync.log"
}

stage_sync() {
    log "repo sync (long)"
    mkdir -p "$LOG"
    cd "$WORK"
    if ! retry 3 sync_once; then
        grep -q '429' "$LOG/sync.log" && echo "HTTP 429 in the log: android.googlesource.com rate-limits anonymous syncs. Set up git cookies (https://android.googlesource.com -> Generate Password -> run the script it shows), lower SYNC_JOBS (now $SYNC_JOBS) and run the stage again."
        die "repo sync keeps failing; see $LOG/sync.log. If it is a Git LFS quota error on the firmware or camera repository, run:
    GIT_LFS_SKIP_SMUDGE=1 $0 sync    and then supply the files by hand (FIRMWARE_DIR for the firmware images)"
    fi
    du -sh "$WORK" 2> /dev/null | tail -1
}

stage_kernel() {
    log "kernel -> $KDIR"
    cd "$WORK"
    local src=${KERNEL_BUNDLE:-$KERNEL_URL}
    [ -n "$src" ] || die "give KERNEL_BUNDLE=/path/to/file.bundle or KERNEL_URL=<git url>"
    if [ ! -d "$KDIR/.git" ]; then
        mkdir -p "$(dirname "$KDIR")"
        git clone -q "$src" "$KDIR"
    fi
    cd "$KDIR"
    if git rev-parse --verify -q "refs/remotes/origin/$KERNEL_BRANCH" > /dev/null; then
        git checkout -q -B "$KERNEL_BRANCH" "origin/$KERNEL_BRANCH"
    else
        git checkout -q "$KERNEL_BRANCH"
    fi
    git reset -q --hard
    git clean -fdxq
    if [ "$KSU" = 1 ]; then
        # the device tree asks for taoyao_defconfig: make that file the root one (kept as a commit here);
        # the SukiSU branch has taoyao_suki_defconfig, the KernelSU-Next branches taoyao_ksu_defconfig
        local ksu_cfg=
        for ksu_cfg in taoyao_suki_defconfig taoyao_ksu_defconfig; do
            [ -f "arch/arm64/configs/$ksu_cfg" ] && break
            ksu_cfg=
        done
        [ -n "$ksu_cfg" ] || die "branch $KERNEL_BRANCH has neither taoyao_suki_defconfig nor taoyao_ksu_defconfig"
        cp "arch/arm64/configs/$ksu_cfg" arch/arm64/configs/taoyao_defconfig
        git add arch/arm64/configs/taoyao_defconfig
        git commit -q -m "taoyao_defconfig: use $ksu_cfg for this build" || true
    fi
    grep -E '^(VERSION|PATCHLEVEL|SUBLEVEL) ' Makefile | tr '\n' ' '
    echo
    git log --oneline -3 | cat
    grep -E '^CONFIG_(KSU|KSU_MANUAL_HOOK|MODULES|KPROBES)(=| )|^# CONFIG_(MODULES|KPROBES|KSU_SUSFS|KPM) ' arch/arm64/configs/taoyao_defconfig || true
}

stage_firmware() {
    log "firmware images"
    cd "$WORK/$FWDIR/images" 2> /dev/null || die "$FWDIR is not there: run the sync stage first"
    local f bad
    count_bad() {
        bad=0
        for f in *.img; do
            if [ "$(stat -c %s "$f")" -lt 4096 ]; then bad=$((bad + 1)); fi
        done
    }
    count_bad
    if [ "$bad" -gt 0 ]; then
        echo "$bad image(s) are Git LFS pointers; trying git lfs pull"
        (cd .. && git lfs pull) || true
        count_bad
    fi
    if [ "$bad" -gt 0 ] && [ -n "$FIRMWARE_DIR" ]; then
        echo "taking the images from $FIRMWARE_DIR"
        for f in *.img; do
            [ -f "$FIRMWARE_DIR/$f" ] && cp "$FIRMWARE_DIR/$f" "$f" || echo "no $f in $FIRMWARE_DIR"
        done
        count_bad
    fi
    [ "$bad" -eq 0 ] || die "$bad firmware image(s) are still LFS pointers. Put the 17 images from the firmware you run (OS1.0.39.0.ULIEUXM) into one folder and set FIRMWARE_DIR (README: how to extract them)"
    ls -l *.img | awk '{print $5, $9}'
    echo "17 expected: $(ls -1 *.img | wc -l) found"
    # the ROM's OTA must carry exactly what is on the phone; these hashes are the ones to compare with a dump
    sha256sum *.img > "$LOG/firmware-sha256.txt"
    echo "hashes saved to $LOG/firmware-sha256.txt"
}

# The six variables Android 16's build system made obsolete; an old device tree that sets one stops the build at once.
OBSOLETE='BOARD_PRODUCT_PREBUILT_DIR|BOARD_SYSTEM_EXT_PREBUILT_DIR|BUILD_BROKEN_GENRULE_SANDBOXING|PRODUCT_ENFORCE_VINTF_MANIFEST_OVERRIDE|PRODUCT_FULL_TREBLE_OVERRIDE|PRODUCT_TREBLE_LINKER_NAMESPACES_OVERRIDE'

stage_preflight() {
    log "preflight"
    cd "$WORK"
    local ok=1
    for d in device/xiaomi/taoyao device/xiaomi/taoyao-camera vendor/xiaomi/taoyao vendor/xiaomi/taoyao-camera \
        "$FWDIR" hardware/xiaomi hardware/dolby "$KDIR" vendor/lineage build/make; do
        [ -d "$d" ] && echo "ok   $d" || { echo "MISSING $d"; ok=0; }
    done
    echo "-- obsolete build variables in the taoyao trees (any hit stops the build; fix or delete the line):"
    grep -rnE "$OBSOLETE" device/xiaomi/taoyao device/xiaomi/taoyao-camera vendor/xiaomi/taoyao-camera hardware/xiaomi hardware/dolby \
        --include='*.mk' --include='*.bp' --include='*.sh' 2> /dev/null | cut -c1-200 || echo "   none"
    echo "-- kernel settings of the device tree:"
    grep -nE 'TARGET_KERNEL|BOARD_KERNEL|BOARD_BOOT_HEADER|BOARD_RAMDISK_USE_LZ4|KERNEL_MODULES' device/xiaomi/taoyao/BoardConfig.mk | cut -c1-160 || true
    echo "-- firmware include (the line that sends 17 firmware partitions into the OTA):"
    grep -n 'taoyao-firmware' device/xiaomi/taoyao/*.mk 2> /dev/null | cut -c1-160 || echo "   not referenced"
    echo "-- resources:"
    echo "   RAM $(awk '/MemTotal/ {printf "%d", $2/1048576}' /proc/meminfo) GB, free disk $(df -BG --output=avail "$WORK" | tail -1 | tr -d ' ') , CPUs $(nproc)"
    echo "   Updater app polls https://raw.githubusercontent.com/crdroidandroid/android_vendor_crDroidOTA/16.0/taoyao.json (404 for an unofficial device; harmless, remove the app later)"
    [ "$ok" = 1 ] || die "something is missing, see above"
}

lunch_env() {
    cd "$WORK"
    export USE_CCACHE=1 CCACHE_EXEC="$(command -v ccache)" LC_ALL=C BUILD_USERNAME=${BUILD_USERNAME:-meru} BUILD_HOSTNAME=${BUILD_HOSTNAME:-crdroid-build}
    ccache -M "${CCACHE_GB:-60}G" > /dev/null 2>&1 || true
    set +e +u
    # shellcheck disable=SC1091
    source build/envsetup.sh > /dev/null
    breakfast taoyao "$VARIANT"
    local rc=$?
    set -e
    return $rc
}

stage_smoke() {
    log "smoke test: breakfast + m nothing"
    mkdir -p "$LOG"
    lunch_env || die "breakfast taoyao failed: a missing dependency or a device tree error; see the output above"
    SECONDS=0
    set +e
    m nothing 2>&1 | tee "$LOG/smoke.log" | tail -25
    local rc=${PIPESTATUS[0]}
    set -e
    echo "m nothing: exit $rc after $((SECONDS / 60)) min; peak memory: watch htop in another tmux window"
    [ "$rc" = 0 ] || die "the smoke test failed; the errors above are the first things to fix (full log: $LOG/smoke.log)"
}

stage_build() {
    log "build: m bacon"
    mkdir -p "$LOG"
    lunch_env || die "breakfast taoyao failed"
    local t="$LOG/build-$(date +%Y%m%d-%H%M%S).log"
    echo "log: $t   (every 150th progress line is shown, plus every failure)"
    SECONDS=0
    set +e
    m bacon 2>&1 | tee "$t" | awk '/^\[ *[0-9]+% /{n++; if (n % 150 == 0) {print; fflush()}; next} /FAILED|error:|Error|ninja: build stopped/{print; fflush()}'
    local rc=${PIPESTATUS[0]}
    set -e
    echo "m bacon: exit $rc after $((SECONDS / 60)) min"
    [ "$rc" = 0 ] || die "the build failed; read the first FAILED block in $t and out/error.log"
    ls -l out/target/product/taoyao/*.zip 2> /dev/null || die "no OTA zip was produced; read the end of $t"
}

stage_collect() {
    log "collect"
    cd "$WORK"
    local P=out/target/product/taoyao A=$WORK/artifacts
    mkdir -p "$A"
    cp -v "$P"/crDroidAndroid-*.zip "$P"/crDroidAndroid-*.zip.sha256sum "$P"/boot.img "$P"/vendor_boot.img "$P"/dtbo.img "$A"/ 2> /dev/null || true
    repo manifest -r -o "$A/manifest-pinned.xml" || true
    git -C "$KDIR" log -1 --format='kernel: %H %s' | tee "$A/kernel.txt"
    (cd "$A" && sha256sum * > SHA256SUMS && cat SHA256SUMS)
    echo
    echo "Fetch them with:   scp -r <user>@<server>:$A ."
}

case ${1:-} in
    check) stage_check ;;
    init) stage_init ;;
    sync) stage_sync ;;
    kernel) stage_kernel ;;
    firmware) stage_firmware ;;
    preflight) stage_preflight ;;
    smoke) stage_smoke ;;
    build) stage_build ;;
    collect) stage_collect ;;
    all) stage_check; stage_init; stage_sync; stage_kernel; stage_firmware; stage_preflight; stage_smoke; stage_build; stage_collect ;;
    *) sed -n '2,32p' "$0"; exit 1 ;;
esac
