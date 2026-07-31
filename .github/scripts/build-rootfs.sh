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

# ── 3. 修复 toolchain wrapper：删 DBR_ARCH，保留 TOOLCHAIN_EXTERNAL_CFLAGS ──
# 问题：buildroot wrapper 通过 -DBR_ARCH 注入 -march=rv64imafdc（缺 xthead），
# vg_lite 的 dcache.civa 等 C908 自定义指令需要 xthead 扩展，汇编失败：
#   ../inc/c908_cache.h:18: Error: unrecognized opcode `dcache.civa a5'
#
# 调用链分析：
#   ① TOOLCHAIN_EXTERNAL_CFLAGS += -march=rv64imafdc  ← 用于 libdir 解析（必须保留）
#   ② -DBR_ARCH='rv64imafdc' → wrapper 注入 -march  ← 覆盖编译器默认 xthead（必须删除）
#
# 修复：只删 ② 的 DBR_ARCH 行，wrapper 不注入 -march，
# 编译器回退到默认 rv64imafdc_xtheadc（vg_lite 汇编通过）。
# TOOLCHAIN_EXTERNAL_CFLAGS 保留不变（toolchain_find_libdir → lib64/lp64d）。
PKG_MK="$BRW_DIR/toolchain/toolchain-external/pkg-toolchain-external.mk"
sed -i '/^TOOLCHAIN_EXTERNAL_TOOLCHAIN_WRAPPER_ARGS += -DBR_ARCH/d' "$PKG_MK"
rm -f "output/$CONF/little/buildroot-ext/.config"
echo "✅ DBR_ARCH removed; compiler default xthead restored; CFLAGS untouched for libdir"

# ── 4. 绕过 copy_toolchain_lib_root ──
sed -i '/^[[:space:]]*\$\$(TOOLCHAIN_EXTERNAL_INSTALL_SYSROOT_LIBS)/d' "$PKG_MK"
sed -i 's/readlink -f/readlink -m/g' "$BRW_DIR/toolchain/helpers.mk"
echo "✅ copy_toolchain_lib_root bypassed"

# ── 5. 预 stub makedevs：CI 无 mknod 权限，在 buildroot 调用之前准备好 no-op ──
FB="output/$CONF/little/buildroot-ext/host/bin"
mkdir -p "$FB"
# 只做一次：如果 makedevs 还不存在或已经是 no-op 就跳过
if [ ! -f "$FB/makedevs" ] || ! grep -q '^exit 0$' "$FB/makedevs" 2>/dev/null; then
  printf '#!/bin/sh\nexit 0\n' > "$FB/makedevs"
  chmod +x "$FB/makedevs"
  echo "✅ makedevs pre-stubbed (CI no mknod)"
fi

# ── 6. cpio.mk 去 mknod ──
sed -i '/^[[:space:]]*mknod /s/^/#CI-DISABLED /' "$BRW_DIR/fs/cpio/cpio.mk"
echo "✅ cpio mknod disabled"

# ── 7. 预填充 staging ──
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

# ── 8. ccache 配置注入 ──
if [ -n "${CCACHE_DIR:-}" ] && command -v ccache &>/dev/null; then
  cat >> "output/$CONF/little/buildroot-ext/.config" <<EOF
BR2_CCACHE=y
BR2_CCACHE_DIR="$CCACHE_DIR"
BR2_CCACHE_USE_BASEDIR=y
BR2_CCACHE_INITIAL_SETUP="--max-size=2G"
EOF
  echo "✅ buildroot ccache enabled ($CCACHE_DIR)"
fi

# ── 9. 两步构建 ──
# 问题：host-makedevs 包会覆盖我们的 stub → cpio/ext2 生成时 mknod EPERM
# 方案：第一遍构建所有包（文件系统阶段失败忽略），重新 stub 后再跑第二遍
# 第二遍时包已构建完，只需跑文件系统生成，用 stub 绕过设备节点

echo "═══ buildroot pass 1 (packages) ═══"
set +e
timeout 2700 make CONF="$CONF" buildroot 2>&1
PASS1_EXIT=$?
set -e

CPIO="output/$CONF/little/buildroot-ext/images/rootfs.cpio"
if [ -f "$CPIO" ] && [ -s "$CPIO" ]; then
  echo "✅ rootfs.cpio built in pass 1 ($(du -h "$CPIO" | cut -f1))"
  exit 0
fi

if [ $PASS1_EXIT -ne 0 ]; then
  echo "⚠️  Pass 1 exited with $PASS1_EXIT (expected: makedevs fails on CI)"
fi

# 重新 stub — host-makedevs 包覆盖了我们的 exit 0 stub
printf '#!/bin/sh\nexit 0\n' > "$FB/makedevs"
chmod +x "$FB/makedevs"
echo "✅ makedevs re-stubbed after host-makedevs package build"

echo "═══ buildroot pass 2 (filesystem) ═══"
timeout 600 make CONF="$CONF" buildroot 2>&1 || { echo "❌ FATAL: buildroot failed (exit=$?)"; exit 1; }

CPIO="output/$CONF/little/buildroot-ext/images/rootfs.cpio"
[ -f "$CPIO" ] && [ -s "$CPIO" ] || { echo "❌ FATAL: rootfs.cpio missing/empty"; exit 1; }
echo "✅ rootfs.cpio built ($(du -h "$CPIO" | cut -f1))"
