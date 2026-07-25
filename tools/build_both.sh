#!/bin/bash
# build_both.sh — 一次性构建烧录包 + 升级包
#
# 用法:
#   ./build_both.sh                          # 完整编译 + 双包
#   ./build_both.sh image-only               # 仅重新打包（跳过完整编译）
#
set -e

CONF=k230_canmv_01studio_defconfig
SDK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${SDK_ROOT}/output/${CONF}/images"
DEST="${DESKTOP:-/mnt/c/Users/13359/Desktop}"
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
cd "$SDK_ROOT"

MODE="${1:-full}"

if [ "$MODE" = "full" ]; then
    echo "=== Full build: $CONF ==="
    make CONF="$CONF"
fi

echo ""
echo "=== Building burn image (Slot A only) ==="
make CONF="$CONF" build-image
BURN_IMG="${OUT_DIR}/sysimage-sdcard.img"
test -f "$BURN_IMG" || { echo "ERROR: burn image not found"; exit 1; }
echo "  OK: $(ls -lh "$BURN_IMG")"

echo ""
echo "=== Building AB upgrade image ==="
BUILD_AB_IMAGE=1 make CONF="$CONF" build-image
AB_IMG="${OUT_DIR}/sysimage-sdcard-ab.img"
test -f "$AB_IMG" || { echo "ERROR: AB image not found"; exit 1; }
AB_SIZE=$(stat -c %s "$AB_IMG")
MIN_SIZE=$((1014 * 1024 * 1024))
[ "$AB_SIZE" -ge "$MIN_SIZE" ] || { echo "ERROR: AB image size $AB_SIZE < $MIN_SIZE"; exit 1; }
echo "  OK: $(ls -lh "$AB_IMG")"

echo ""
echo "=== Building OTA package ==="
bash "${SDK_ROOT}/tools/build_ota_package.sh" "$OUT_DIR"
OTA_PKG=$(ls -t "${OUT_DIR}"/k230_ota_ab_*.tar.gz 2>/dev/null | head -1)
test -f "$OTA_PKG" || { echo "WARNING: OTA package not found (non-fatal)"; }

# 复制到桌面
if [ -d "${DEST:-/nonexistent}" ]; then
    echo ""
    echo "=== Copying to Desktop ==="
    cp -v "$BURN_IMG"  "$DEST/sysimage-sdcard-burn.img"
    cp -v "$AB_IMG"    "$DEST/sysimage-sdcard-ab.img"
    [ -f "$OTA_PKG" ] && cp -v "$OTA_PKG" "$DEST/"
fi

echo ""
echo "=== ALL DONE ==="
echo "Burn image:  $(ls -lh "$BURN_IMG")"
echo "AB image:    $(ls -lh "$AB_IMG")"
[ -f "$OTA_PKG" ] && echo "OTA package: $(ls -lh "$OTA_PKG")"
