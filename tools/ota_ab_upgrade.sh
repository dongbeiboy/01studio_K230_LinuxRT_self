#!/bin/sh
# ota_ab_upgrade.sh — A/B OTA 升级（目标板执行）
# 用法: ota_ab_upgrade.sh /path/to/k230_ota_ab_YYYYMMDD.tar.gz
# 特点: 管道直写不落盘（避免 rootfs 空间不足）
set -e

error_exit() { echo "OTA FAILED: $1"; exit 1; }

[ $# -ge 1 ] || error_exit "usage: $0 <tarball>"
TARBALL="$1"
[ -f "$TARBALL" ] || error_exit "$TARBALL not found"

LOCKFILE=/tmp/ota_upgrade.lock
exec 200>"$LOCKFILE"
flock -n 200 || error_exit "another OTA is running"

echo "=== A/B OTA Upgrade ==="

# 1. 校验完整性 + 只提取小文件
echo "[1/5] Verifying package..."
gzip -t "$TARBALL" || error_exit "gzip integrity check failed"

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

gzip -dc "$TARBALL" | tar xf - -C "$TMPD" checksum.sha256 VERSION 2>/dev/null
[ -f "$TMPD/checksum.sha256" ] || error_exit "missing checksum.sha256"
[ -f "$TMPD/VERSION" ] || error_exit "missing VERSION"

for FILE in rtt_system.bin linux_system.bin rootfs.ext4; do
    EXPECT=$(grep "$FILE" "$TMPD/checksum.sha256" | awk '{print $1}')
    ACTUAL=$(gzip -dc "$TARBALL" | tar xf - -O "$FILE" 2>/dev/null | sha256sum | awk '{print $1}')
    [ "$ACTUAL" = "$EXPECT" ] || error_exit "sha256 mismatch: $FILE"
    echo "  $FILE: OK"
done

# 2. 版本检查
echo "[2/5] Checking version..."
parse_ver() { echo "$1" | sed 's/[^0-9]//g'; }
CUR_VER=$(parse_ver "$(cat /etc/version/release_version 2>/dev/null | head -1 || echo "0")")
NEW_VER=$(parse_ver "$(cat "$TMPD/VERSION")")
CUR_VER=${CUR_VER:-0}; NEW_VER=${NEW_VER:-0}
[ "$CUR_VER" -lt "$NEW_VER" ] || error_exit "version downgrade: $CUR_VER >= $NEW_VER"
echo "  $CUR_VER → $NEW_VER"

# 3. 目标槽
echo "[3/5] Determining target slot..."
CUR_SLOT=$(fw_printenv -n boot_slot 2>/dev/null || echo "a")
case "$CUR_SLOT" in
  a) TARGET=b; R_S=$((384*1024*1024/512)); L_S=$((404*1024*1024/512)); F_S=502 ;;
  b) TARGET=a; R_S=$((10*1024*1024/512));  L_S=$((30*1024*1024/512));  F_S=128 ;;
  *) error_exit "invalid current slot: $CUR_SLOT" ;;
esac
echo "  $CUR_SLOT → $TARGET"

# 4. 管道直写（tar → dd，不落盘）
echo "[4/5] Writing to slot $TARGET..."
gzip -dc "$TARBALL" | tar xf - -O rtt_system.bin 2>/dev/null \
    | dd of=/dev/mmcblk0 bs=512 seek=$R_S conv=fsync 2>/dev/null || error_exit "rtt write failed"
echo "  rtt: OK"

gzip -dc "$TARBALL" | tar xf - -O linux_system.bin 2>/dev/null \
    | dd of=/dev/mmcblk0 bs=512 seek=$L_S conv=fsync 2>/dev/null || error_exit "linux write failed"
echo "  linux: OK"

gzip -dc "$TARBALL" | tar xf - -O rootfs.ext4 2>/dev/null \
    | dd of=/dev/mmcblk0 bs=1M seek=$F_S conv=fsync 2>/dev/null || error_exit "rootfs write failed"
sync
echo "  rootfs: OK"

# 5. 读回校验
echo "[5/5] Verifying written data..."
G_R=$(grep rtt_system.bin "$TMPD/checksum.sha256" | awk '{print $1}')
G_L=$(grep linux_system.bin "$TMPD/checksum.sha256" | awk '{print $1}')
G_F=$(grep rootfs.ext4 "$TMPD/checksum.sha256" | awk '{print $1}')

A_R=$(dd if=/dev/mmcblk0 bs=512 skip=$R_S count=$((20*1024*1024/512)) 2>/dev/null | sha256sum | awk '{print $1}')
[ "$A_R" = "$G_R" ] || error_exit "rtt verify FAIL"
echo "  rtt: OK"

A_L=$(dd if=/dev/mmcblk0 bs=512 skip=$L_S count=$((50*1024*1024/512)) 2>/dev/null | sha256sum | awk '{print $1}')
[ "$A_L" = "$G_L" ] || error_exit "linux verify FAIL"
echo "  linux: OK"

A_F=$(dd if=/dev/mmcblk0 bs=512 skip=$((F_S*2048)) count=$((256*1024*1024/512)) 2>/dev/null | sha256sum | awk '{print $1}')
[ "$A_F" = "$G_F" ] || error_exit "rootfs verify FAIL"
echo "  rootfs: OK"

# 6. 事务性 env
echo "  Setting boot_slot=$TARGET..."
fw_setenv "boot_slot_${TARGET}_attempt" 3 || error_exit "env write failed"
fw_setenv boot_slot "$TARGET"            || error_exit "env write failed"
fw_setenv boot_attempt_max 3             || error_exit "env write failed"

echo ""
echo "=== OTA SUCCESS: will boot slot $TARGET ==="
echo "Run 'reboot' now."
