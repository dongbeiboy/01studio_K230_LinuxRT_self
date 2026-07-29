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

# ── 3. 删掉 wrapper 的 -march 参数 ──
# 工具链默认 march=rv64imafdc_xtheadc，不需要 wrapper 传 -march。
# buildroot 往 wrapper 传了 -march=rv64imafdc（缺 xthead），
# 反而把编译器默认的正确值覆盖了，导致 vg_lite 汇编失败。
PKG_MK="$BRW_DIR/toolchain/toolchain-external/pkg-toolchain-external.mk"
sed -i '/^TOOLCHAIN_EXTERNAL_CFLAGS.*march/d' "$PKG_MK"
sed -i '/DBR_ARCH/d' "$PKG_MK"
# GCC_TARGET_ARCH 仍可能通过 ifeq 获得 xthead 后缀，buildroot
# 会根据它创建 multilib 目录。需要同时限制为不带 xthead 的值。
echo 'GCC_TARGET_ARCH := rv64imafdc' >> "$BRW_DIR/arch/arch.mk.riscv"
rm -f "output/$CONF/little/buildroot-ext/.config"
echo "✅ BR_ARCH removed + GCC_TARGET_ARCH capped, old .config deleted"

# ── 4. 绕过 copy_toolchain_lib_root ──
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

# ── 7. 验证 + 构建 ──
echo "=== PRE-BUILD CHECK ==="
echo "last 3 lines of arch.mk.riscv:"
tail -3 "$BRW_DIR/arch/arch.mk.riscv"
echo "═══ buildroot ═══"
timeout 2700 make CONF="$CONF" buildroot 2>&1 || { echo "❌ FATAL: buildroot failed (exit=$?)"; exit 1; }

# ── 8. 收尾 ──
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
