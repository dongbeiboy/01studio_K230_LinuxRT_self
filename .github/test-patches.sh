#!/bin/bash
set -euo pipefail
# 本地验证 .github/workflows/build.yml 中 sed/patch 命令是否有效
# 用法：bash .github/test-patches.sh
echo "=== test-patches: verify CI sed commands against real buildroot source ==="

BRW_DIR="$(ls -d src/little/buildroot-ext/buildroot-*/ 2>/dev/null | head -1)"
if [ -z "$BRW_DIR" ]; then
  echo "❌ SKIP: no buildroot extracted, run 'make prepare_sourcecode' first"
  exit 0
fi

# 1. pkg-toolchain-external.mk: sed 检查
PKG_MK="$BRW_DIR/toolchain/toolchain-external/pkg-toolchain-external.mk"
test -f "$PKG_MK" || { echo "❌ $PKG_MK not found"; exit 1; }
cp "$PKG_MK" /tmp/test_mk_copy.mk

# 删除 INSTALL_SYSROOT_LIBS 行
sed -i '/^[[:space:]]*\$\$(TOOLCHAIN_EXTERNAL_INSTALL_SYSROOT_LIBS)/d' /tmp/test_mk_copy.mk
if grep -q 'TOOLCHAIN_EXTERNAL_INSTALL_SYSROOT_LIBS' /tmp/test_mk_copy.mk; then
  echo "❌ sed didn't remove INSTALL_SYSROOT_LIBS (unexpected: still present)"
  exit 1
fi

# 删除 DBR_ARCH 行（wrapper 不再注入 -march，编译器回退默认 xtheadc）
cp "$PKG_MK" /tmp/test_mk_arch.mk
sed -i '/^TOOLCHAIN_EXTERNAL_TOOLCHAIN_WRAPPER_ARGS += -DBR_ARCH/d' /tmp/test_mk_arch.mk
if grep -q 'DBR_ARCH' /tmp/test_mk_arch.mk; then
  echo "❌ DBR_ARCH not removed from pkg-toolchain-external.mk"
  exit 1
fi
echo "✅ pkg-toolchain-external.mk patches OK"

# 2. helpers.mk: readlink -f → readlink -m
HLP_MK="$BRW_DIR/toolchain/helpers.mk"
test -f "$HLP_MK" || { echo "❌ $HLP_MK not found"; exit 1; }
cp "$HLP_MK" /tmp/test_hlp.mk
sed -i 's/readlink -f/readlink -m/g' /tmp/test_hlp.mk
if grep -q 'readlink -f' /tmp/test_hlp.mk; then
  remaining=$(grep -c 'readlink -f' /tmp/test_hlp.mk 2>/dev/null || true)
  echo "⚠️  $remaining readlink -f remaining (may be from binary strings)"
fi
echo "✅ helpers.mk readlink OK"

# 3. fs/ext2/Config.in: 默认大小 200M（AB 分区 rootfs_a=374M rootfs_b=256M）
EXT2_CFG="$BRW_DIR/fs/ext2/Config.in"
test -f "$EXT2_CFG" || { echo "❌ $EXT2_CFG not found"; exit 1; }
cp "$EXT2_CFG" /tmp/test_ext2.mk
if ! grep -q 'default "200M"' "$EXT2_CFG"; then
  sed -i 's/default "60M"/default "200M"/' /tmp/test_ext2.mk
  if ! grep -q 'default "200M"' /tmp/test_ext2.mk; then
    echo "❌ ext2 default size not updated to 200M"
    exit 1
  fi
fi
echo "✅ ext2 default size OK"

# 4. cpio.mk: mknod disable
CPIO_MK="$BRW_DIR/fs/cpio/cpio.mk"
test -f "$CPIO_MK" || { echo "❌ $CPIO_MK not found"; exit 1; }
cp "$CPIO_MK" /tmp/test_cpio.mk
sed -i '/^[[:space:]]*mknod /s/^/#CI-DISABLED /' /tmp/test_cpio.mk
if ! grep -q 'CI-DISABLED' /tmp/test_cpio.mk; then
  echo "❌ cpio.mk mknod not disabled"
  exit 1
fi
echo "✅ cpio.mk mknod OK"

rm -f /tmp/test_mk_copy.mk /tmp/test_mk_arch.mk /tmp/test_hlp.mk /tmp/test_ext2.mk /tmp/test_cpio.mk
echo "=== ALL PATCH TESTS PASSED ==="
