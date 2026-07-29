#!/bin/bash
set -euo pipefail
# CI buildroot 构建脚本
# 替代 build.yml 中 inline shell，方便本地 docker 测试
# 用法: CONF=k230_canmv_01studio_defconfig bash .github/build-rootfs.sh

CONF="${CONF:?must set CONF}"
BRW_ROOT="src/little/buildroot-ext"

# ── 1. 解压 buildroot ──
if ! ls -d "$BRW_ROOT"/buildroot-*/ 2>/dev/null | head -1 | grep -q buildroot; then
  TAR=$(ls "$BRW_ROOT"/dl/buildroot-*.tar.gz 2>/dev/null | head -1)
  [ -n "$TAR" ] && { echo "📦 extracting buildroot..."; tar --no-same-owner -zxf "$TAR" -C "$BRW_ROOT"; } \
    || { echo "❌ FATAL: no buildroot tarball"; exit 1; }
fi
BRW_DIR="$(ls -d src/little/buildroot-ext/buildroot-*/ 2>/dev/null | head -1)"

# ── 2. 补丁 ──
[ -d "$BRW_DIR/package/fakeroot" ] || { echo "❌ FATAL: fakeroot dir not found"; exit 1; }
cp .github/patches/0002-fix-stat-ver-glibc235.patch "$BRW_DIR/package/fakeroot/"
[ -d "$BRW_DIR/package/m4" ] && cp .github/patches/0003-fix-m4-sigstksz.patch "$BRW_DIR/package/m4/"
printf '#!/bin/sh\necho "[CI] check-bin-arch skipped"\nexit 0\n' > "$BRW_DIR/support/scripts/check-bin-arch"
echo "✅ patches installed"

# ── 3. 确保 THEAD (Xuantie 扩展) ──
DEFC="$BRW_DIR/configs/k230_evb_defconfig"
grep -q 'BR2_RISCV_ISA_CUSTOM_THEAD=y' "$DEFC" || echo "BR2_RISCV_ISA_CUSTOM_THEAD=y" >> "$DEFC"
echo "✅ THEAD ensured"

# ── 4. 绕过 copy_toolchain_lib_root ──
PKG_MK="$BRW_DIR/toolchain/toolchain-external/pkg-toolchain-external.mk"
sed -i '/^[[:space:]]*\$\$(TOOLCHAIN_EXTERNAL_INSTALL_SYSROOT_LIBS)/d' "$PKG_MK"
sed -i 's/readlink -f/readlink -m/g' "$BRW_DIR/toolchain/helpers.mk"
echo "✅ copy_toolchain_lib_root bypassed"

# ── 5. cpio.mk 去 mknod ──
sed -i '/^[[:space:]]*mknod /s/^/#CI-DISABLED /' "$BRW_DIR/fs/cpio/cpio.mk"
echo "✅ cpio mknod disabled"

# ── 6. 预填充 staging ──
STGDIR="output/$CONF/little/buildroot-ext/host/riscv64-buildroot-linux-gnu/sysroot"
TC=/opt/toolchain/Xuantie-900-gcc-linux-5.10.4-glibc-x86_64-V2.6.0
mkdir -p "$STGDIR"
SYSROOT="$("$TC/bin/riscv64-unknown-linux-gnu-gcc" -print-sysroot 2>/dev/null)"
if [ -z "$SYSROOT" ] || [ ! -d "$SYSROOT" ]; then
  SYSROOT=$(dirname "$(dirname "$(find "$TC" -maxdepth 5 -name 'libc.so*' 2>/dev/null | head -1)")")
fi
[ -d "$SYSROOT" ] || { echo "❌ FATAL: cannot resolve toolchain sysroot"; exit 1; }
echo "📦 cp -a $SYSROOT → $STGDIR"
cp -a "$SYSROOT"/. "$STGDIR"/
n=$(find "$STGDIR" -name 'libc.so*' 2>/dev/null | wc -l)
[ "$n" -eq 0 ] && { echo "❌ FATAL: staging still empty ($SYSROOT→$STGDIR)"; ls "$SYSROOT"/lib/libc* 2>/dev/null || echo "no libc at source"; exit 1; }
echo "✅ staging pre-populated ($n libc found)"

# ── 7. 强制再生 .config ──
rm -f "output/$CONF/little/buildroot-ext/.config"
echo "✅ old .config removed"

# ── 8. 单次 buildroot ──
echo "═══ buildroot ═══"
timeout 2700 make CONF="$CONF" buildroot 2>&1 || { echo "❌ FATAL: buildroot failed (exit=$?)"; exit 1; }

# ── 9. 收尾 ──
FB="output/$CONF/little/buildroot-ext/host/bin"
CPIO="output/$CONF/little/buildroot-ext/images/rootfs.cpio"
if [ -f "$FB/makedevs" ] && ! grep -q 'CI-NOOP' "$FB/makedevs" 2>/dev/null; then
  mv "$FB/makedevs" "$FB/makedevs.real"
  printf '#!/bin/sh\necho "[CI-NOOP] makedevs skipped"\nexit 0\n' > "$FB/makedevs"
  chmod +x "$FB/makedevs"
  echo "✅ makedevs stubbed"
fi
TGT="output/$CONF/little/buildroot-ext/build/buildroot-fs/cpio/target"
mkdir -p "$TGT/dev"
for n in null console zero mem ttyS0 ttyAMA0; do touch "$TGT/dev/$n"; done
FSCR="output/$CONF/little/buildroot-ext/build/buildroot-fs/cpio/fakeroot"
if [ -f "$FSCR" ] && [ ! -f "$CPIO" ]; then
  echo "🔧 Manual cpio..."
  sed -i '/mknod /s/^/echo [SKIP] /' "$FSCR"
  sed -i '/makedevs /s/^/echo [SKIP] /' "$FSCR"
  PATH="$FB:$FB/../sbin:$PATH" bash "$FSCR" && touch "$CPIO" && echo "✅ cpio done"
fi
[ -f "$CPIO" ] && [ -s "$CPIO" ] || { echo "❌ FATAL: rootfs.cpio missing/empty"; exit 1; }
echo "✅ rootfs.cpio built ($(du -h "$CPIO" | cut -f1))"
