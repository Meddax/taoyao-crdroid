#!/usr/bin/env bash
# Prepares a fresh Ubuntu 24.04 (or 22.04) server for the crDroid build: packages, the repo tool, git-lfs,
# a swap file when RAM is short, ccache, and an unprivileged user "build" that owns the work.
#
#   sudo bash server_setup.sh
#
# It changes nothing else on the machine. Run it once, as root.
set -euo pipefail

[ "$(id -u)" = 0 ] || { echo "run as root: sudo bash $0" >&2; exit 1; }
. /etc/os-release
case "${VERSION_ID:-}" in
    22.04 | 24.04) ;;
    *) echo "this script was written for Ubuntu 22.04/24.04, this is ${PRETTY_NAME:-unknown}; carry on at your own risk" >&2 ;;
esac

MEM_GB=$(awk '/MemTotal/ {printf "%d", $2 / 1048576}' /proc/meminfo)
FREE_GB=$(df -BG --output=avail /home | tail -1 | tr -dc 0-9)
echo "RAM ${MEM_GB} GB, free disk under /home ${FREE_GB} GB, $(nproc) CPUs"
[ "$FREE_GB" -ge 350 ] || echo "WARNING: less than 350 GB free: the tree and out/ need about 250 + 150 GB (400 GB is the documented minimum)" >&2
[ "$MEM_GB" -ge 60 ] || echo "WARNING: less than 64 GB RAM: Soong's analysis may thrash; a swap file is added below" >&2

echo "== packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
# LineageOS wiki (lineage-21 and newer), plus the tools this kit uses
apt-get install -y -qq bc bison build-essential ccache curl erofs-utils flex g++-multilib gcc-multilib git git-lfs \
    gnupg gperf imagemagick kmod protobuf-compiler python3-protobuf lib32readline-dev lib32z1-dev libdw-dev \
    libelf-dev libgnutls28-dev lz4 libsdl1.2-dev libssl-dev libxml2 libxml2-utils lzop pngcrush rsync schedtool \
    squashfs-tools xsltproc xxd zip zlib1g-dev python-is-python3 \
    tmux unzip jq htop

echo "== repo"
if ! command -v repo > /dev/null; then
    curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o /usr/local/bin/repo
    chmod a+rx /usr/local/bin/repo
fi
repo --version 2> /dev/null | head -2 || true

echo "== git-lfs"
git lfs install --system

SWAP_GB=${SWAP_GB:-32}
CCACHE_GB=${CCACHE_GB:-60}
ZRAM_GB=${ZRAM_GB:-0}
if [ "$MEM_GB" -lt 60 ] && [ ! -f /swapfile ]; then
    echo "== swap file (${SWAP_GB} GB)"
    fallocate -l "${SWAP_GB}G" /swapfile
    chmod 600 /swapfile
    mkswap /swapfile > /dev/null
    swapon -p 10 /swapfile
    grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw,pri=10 0 0' >> /etc/fstab
fi
if [ "$ZRAM_GB" -gt 0 ] && ! swapon --show | grep -q zram; then
    # compressed swap in RAM, used before the disk swap: Soong's analysis is what needs it
    echo "== zram swap (${ZRAM_GB} GB)"
    modprobe zram
    echo lzo-rle > /sys/block/zram0/comp_algorithm 2> /dev/null || true
    echo "${ZRAM_GB}G" > /sys/block/zram0/disksize
    mkswap /dev/zram0 > /dev/null
    swapon -p 100 /dev/zram0
    echo "(zram is gone after a restart of the machine; run:  sudo ZRAM_GB=$ZRAM_GB bash $0  again)"
fi
swapon --show

echo "== user build"
id build > /dev/null 2>&1 || adduser --disabled-password --gecos "" build
usermod -aG sudo build
echo 'build ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/build
chmod 440 /etc/sudoers.d/build
sudo -u build CCACHE_GB="$CCACHE_GB" bash -c '
    git config --global user.name  "meru-build"
    git config --global user.email "build@localhost"
    git config --global color.ui false
    git config --global core.compression 0
    # a stalled connection must fail (and be retried by repo) instead of hanging for hours
    git config --global http.lowSpeedLimit 2000
    git config --global http.lowSpeedTime 60
    git config --global gc.auto 0
    grep -q USE_CCACHE ~/.bashrc || cat >> ~/.bashrc <<RC

# crDroid build
export USE_CCACHE=1
export CCACHE_EXEC=/usr/bin/ccache
export CCACHE_GB=$CCACHE_GB
export LC_ALL=C
export BUILD_USERNAME=meru
export BUILD_HOSTNAME=crdroid-build
RC
    ccache -M "${CCACHE_GB}G" > /dev/null
'

echo
echo "Done. Next, as user build:   sudo -iu build   (or: su - build)"
echo "then copy the kit and the kernel bundle there and run build_crdroid.sh inside tmux (see README.md)."
