#!/bin/bash
set -euo pipefail
# 一键完整编译 K230 SDK (Linux + RTT + Buildroot + AB 镜像)
# 用法: bash build_all.sh [选项] [defconfig]
#
# 选项:
#   --clean      清空 output/ 后全新构建
#   --ab-only    仅打包 AB 镜像 + OTA（跳过编译，需要已有产物）
#   --rootfs-only 仅编译 buildroot（跳过 Linux/U-Boot/RTT）
#   -h, --help   显示帮助
#
# 示例:
#   bash build_all.sh                                      # 默认 defconfig，增量编译
#   bash build_all.sh --clean                              # 全新编译
#   bash build_all.sh --ab-only                            # 只打包镜像
#   bash build_all.sh k230_evb_defconfig                   # 指定 defconfig
#   bash build_all.sh --clean k230_canmv_defconfig         # 指定 defconfig + 全新编译
#   bash build_all.sh --rootfs-only                        # 只编 rootfs

CLEAN=false
AB_ONLY=false
ROOTFS_ONLY=false
CONF=""

while [ $# -gt 0 ]; do
  case "$1" in
    --clean)    CLEAN=true; shift ;;
    --ab-only)  AB_ONLY=true; shift ;;
    --rootfs-only) ROOTFS_ONLY=true; shift ;;
    -h|--help)  head -20 "$0" | grep '^#' | sed 's/^# \?//'; exit 0 ;;
    -*)         echo "未知选项: $1"; head -15 "$0" | grep '^#' | sed 's/^# \?//'; exit 2 ;;
    *)          CONF="$1"; shift ;;
  esac
done
CONF="${CONF:-k230_canmv_01studio_defconfig}"

K230_SDK_ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$K230_SDK_ROOT/output/$CONF"
TOOLCHAIN_DIR="$K230_SDK_ROOT/toolchain"

export CONF K230_SDK_ROOT BUILD_DIR

# ── 干净 PATH（WSL 注意：Windows 路径含括号会炸 shell，不要加 /mnt/* 到 PATH）──
export PATH="/opt/toolchain/riscv64-linux-musleabi_for_x86_64-pc-linux-gnu/bin:/opt/toolchain/Xuantie-900-gcc-linux-5.10.4-glibc-x86_64-V2.6.0/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"

echo "╔══════════════════════════════════════════╗"
echo "║  K230 SDK 一键编译: $CONF"
[ "$CLEAN" = true ]   && echo "║  🧹 clean enabled"
[ "$AB_ONLY" = true ]  && echo "║  📦 AB 镜像 only"
[ "$ROOTFS_ONLY" = true ] && echo "║  🌱 rootfs only"
echo "╚══════════════════════════════════════════╝"

# ── 工具链 ──
if [ ! -f /opt/toolchain/Xuantie-900-gcc-linux-5.10.4-glibc-x86_64-V2.6.0/bin/riscv64-unknown-linux-gnu-gcc ]; then
  echo "🔗 链接工具链..."
  mkdir -p /opt/toolchain
  ln -sfn "$TOOLCHAIN_DIR/Xuantie-900-gcc-linux-5.10.4-glibc-x86_64-V2.6.0" /opt/toolchain/
  ln -sfn "$TOOLCHAIN_DIR/riscv64-linux-musleabi_for_x86_64-pc-linux-gnu" /opt/toolchain/
fi

if [ "$CLEAN" = true ]; then
  rm -rf "$BUILD_DIR"
  echo "🧹 $BUILD_DIR cleaned"
fi

START_TS=$(date +%s)
TOTAL=5
log_step() { echo ""; echo "▶ [$1/$TOTAL] $2 ..."; }

if [ "$AB_ONLY" = true ]; then
  log_step 5 "AB 镜像 + OTA 包 (skip build)"
  BUILD_AB_IMAGE=1 make CONF="$CONF" build-image
  bash "$K230_SDK_ROOT/tools/build_ota_package.sh"
elif [ "$ROOTFS_ONLY" = true ]; then
  log_step 4 "Buildroot (rootfs)"
  bash "$K230_SDK_ROOT/.github/scripts/build-rootfs.sh"
  log_step 5 "AB 镜像 + OTA 包"
  BUILD_AB_IMAGE=1 make CONF="$CONF" build-image
  bash "$K230_SDK_ROOT/tools/build_ota_package.sh"
else
  # ── 完整流水线 ──
  log_step 1 "小核 Linux"
  make CONF="$CONF" linux

  log_step 2 "小核 U-Boot + OpenSBI"
  make CONF="$CONF" little-core-opensbi uboot

  log_step 3 "大核 RTT + MPP + CDK"
  make CONF="$CONF" mpp rt-smart cdk-user

  log_step 4 "Buildroot (rootfs)"
  bash "$K230_SDK_ROOT/.github/scripts/build-rootfs.sh"

  log_step 5 "AB 镜像 + OTA 包"
  BUILD_AB_IMAGE=1 make CONF="$CONF" build-image
  bash "$K230_SDK_ROOT/tools/build_ota_package.sh"
fi

# ── 结果 ──
ELAPSED=$(($(date +%s) - START_TS))
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  ✅ 全部完成! ($(date -ud @$ELAPSED +%H:%M:%S))"
echo "╠══════════════════════════════════════════╣"
echo "║  AB 镜像:   sysimage-sdcard-ab.img.gz"
echo "║  OTA 包:    k230_ota_ab_*.tar.gz"
echo "╚══════════════════════════════════════════╝"
ls -lh "$BUILD_DIR/images/sysimage-sdcard-ab.img.gz" "$BUILD_DIR/images"/k230_ota_ab_*.tar.gz 2>/dev/null || echo "⚠️  部分产物缺失"
