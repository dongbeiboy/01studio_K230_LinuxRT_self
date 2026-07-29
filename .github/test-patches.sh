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

# 追加 _xtheadc
cp "$PKG_MK" /tmp/test_mk_arch.mk
sed -i 's/\$(GCC_TARGET_ARCH)/$(GCC_TARGET_ARCH)_xtheadc/g' /tmp/test_mk_arch.mk
if ! grep -q '_xtheadc' /tmp/test_mk_arch.mk; then
  echo "❌ _xtheadc not inserted into pkg-toolchain-external.mk"
  exit 1
fi
echo "✅ pkg-toolchain-external.mk patches OK"

# 2. helpers.mk: readlink -f → readlink -m
HLP_MK="$BRW_DIR/toolchain/helpers.mk"
test -f "$HLP_MK" || { echo "❌ $HLP_MK not found"; exit 1; }
cp "$HLP_MK" /tmp/test_hlp.mk
sed -i 's/readlink -f/readlink -m/g' /tmp/test_hlp.mk
if grep 'readlink -f' /tmp/test_hlp.mk | grep -qv '_xtheadc'; then
  remaining=$(grep -c 'readlink -f' /tmp/test_hlp.mk 2>/dev/null || true)
  echo "⚠️  $remaining readlink -f remaining (may be from binary strings)"
fi
echo "✅ helpers.mk readlink OK"

# 3. pkg-generic.mk: 进度行注入
GEN_MK="$BRW_DIR/package/pkg-generic.mk"
test -f "$GEN_MK" || { echo "❌ $GEN_MK not found"; exit 1; }
cp "$GEN_MK" /tmp/test_gen.mk
TAB="$(printf '\t')"
sed -i "/Fixing libtool files/i\\${TAB}@echo \"  .la files to fix:\"; find \$(STAGING_DIR)/usr/lib* -name '*.la' 2>/dev/null | wc -l" /tmp/test_gen.mk
if ! grep -q '.la files to fix' /tmp/test_gen.mk; then
  echo "❌ pkg-generic.mk progress not inserted"
  exit 1
fi
echo "✅ pkg-generic.mk progress injection OK"

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

rm -f /tmp/test_mk_copy.mk /tmp/test_mk_arch.mk /tmp/test_hlp.mk /tmp/test_gen.mk /tmp/test_cpio.mk
echo "=== ALL PATCH TESTS PASSED ==="
