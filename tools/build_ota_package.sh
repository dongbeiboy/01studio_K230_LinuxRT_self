#!/bin/bash
# build_ota_package.sh — 构建 OTA 升级包
#
# 从编译产物中提取 RTT、Linux、rootfs，补齐到槽位大小后打包
# 用法: ./build_ota_package.sh [output_dir]
#
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SDK_ROOT="$(dirname "$SCRIPT_DIR")"
IMAGES_DIR="${1:-${SDK_ROOT}/output/k230_canmv_01studio_defconfig/images}"

PARTITION_LAYOUT="${SDK_ROOT}/board/common/gen_image_cfg/partition_layout.sh"
if [ -f "$PARTITION_LAYOUT" ]; then
    source "$PARTITION_LAYOUT"
else
    echo "ERROR: partition_layout.sh not found"
    exit 1
fi

RTT_SIZE=$((20 * 1024 * 1024))
LINUX_SIZE=$((50 * 1024 * 1024))
ROOTFS_SIZE=$((256 * 1024 * 1024))

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

cd "$WORKDIR"

echo "=== Building OTA package ==="

# 复制编译产物
cp "${IMAGES_DIR}/big-core/rtt_system.bin"       rtt_system.bin
cp "${IMAGES_DIR}/little-core/linux_system.bin"  linux_system.bin
cp "${IMAGES_DIR}/little-core/rootfs.ext4"       rootfs.ext4

# 补齐到槽位大小（确保 OTA 校验时哈希一致）
echo "Padding files to slot sizes..."
truncate -s $RTT_SIZE    rtt_system.bin
truncate -s $LINUX_SIZE  linux_system.bin
truncate -s $ROOTFS_SIZE rootfs.ext4

# 校验大小
check_size() {
    local f="$1" expected="$2"
    local actual=$(stat -c %s "$f")
    if [ "$actual" -ne "$expected" ]; then
        echo "ERROR: $f size $actual != expected $expected"
        exit 1
    fi
}
check_size rtt_system.bin   $RTT_SIZE
check_size linux_system.bin $LINUX_SIZE
check_size rootfs.ext4      $ROOTFS_SIZE

# 生成校验和
sha256sum rtt_system.bin linux_system.bin rootfs.ext4 > checksum.sha256

# 版本号
echo "AB-v2.0-$(date +%Y%m%d)" > VERSION

# 打包
PACKAGE_NAME="k230_ota_ab_$(date +%Y%m%d).tar.gz"
tar czf "$PACKAGE_NAME" rtt_system.bin linux_system.bin rootfs.ext4 checksum.sha256 VERSION

# 复制到 images 目录（临时目录会被 trap 清理）
cp "$PACKAGE_NAME" "${IMAGES_DIR}/"
PACKAGE_PATH="${IMAGES_DIR}/${PACKAGE_NAME}"
PACKAGE_SIZE=$(stat -c %s "$PACKAGE_PATH")
echo ""
echo "=== OTA package ready ==="
echo "  File:   ${PACKAGE_PATH}"
echo "  Size:   $(numfmt --to=iec ${PACKAGE_SIZE})"
echo "  MD5:    $(md5sum "${PACKAGE_PATH}" | awk '{print $1}')"
echo ""
echo "  Deploy to target and run: ota_ab_upgrade.sh $PACKAGE_NAME"
