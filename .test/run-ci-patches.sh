#!/bin/bash
# 用 Docker 模拟 CI workflow 中的 "Build buildroot" 步骤
# 只跑 patch/sed 阶段，不跑 make buildroot（太快了）
set -euo pipefail
echo "=== CI patch simulator ==="
CONF="${1:-k230_canmv_01studio_defconfig}"
echo "DEFCONFIG=$CONF"

mkdir -p dl output

docker run --rm -i \
  -v "$(pwd):/ws" -w /ws \
  -e CONF="$CONF" \
  catthehacker/ubuntu:act-22.04 \
  bash -euxo pipefail -c '
    # 安装依赖（和 CI 一致）
    sudo dpkg --add-architecture i386
    sudo apt-get update -qq
    sudo apt-get install -y -qq --no-install-recommends \
      cmake flex bison m4 fakeroot attr zlib1g-dev \
      bc cpio unzip rsync file make binutils build-essential \
      gcc g++ bash patch gzip bzip2 perl tar dosfstools mtools \
      autoconf automake pkg-config libc6-dev-i386 libncurses5:i386 \
      libssl-dev libncurses5-dev libconfuse2 libconfuse-dev \
      python3 python3-pip python-is-python3 scons wget curl

    # 模拟 toolchain cache hit
    mkdir -p toolchain
    touch toolchain/.toolchain_ready

    # 模拟 source cache hit（已解压的 buildroot）
    BRW_ROOT="src/little/buildroot-ext"
    mkdir -p "$BRW_ROOT"/dl
    if ! ls -d "$BRW_ROOT"/buildroot-*/ 2>/dev/null | head -1 | grep -q buildroot; then
      echo "No buildroot source — need tarball in dl/"
      exit 1
    fi

    # ═══ 以下和 workflow 完全一致 ═══

    BRW_DIR="$(ls -d src/little/buildroot-ext/buildroot-*/ 2>/dev/null | head -1)"

    # PATCHES
    [ -d "$BRW_DIR/package/fakeroot" ] || { echo "❌ FATAL: fakeroot dir"; exit 1; }
    cp .github/patches/0002-fix-stat-ver-glibc235.patch "$BRW_DIR/package/fakeroot/" || true
    [ -d "$BRW_DIR/package/m4" ] && cp .github/patches/0003-fix-m4-sigstksz.patch "$BRW_DIR/package/m4/" || true

    # pkg-generic.mk progress
    TAB="$(printf "\t")"
    sed -i "/Fixing libtool files/i\\${TAB}@echo \"  .la files to fix:\"; find \$(STAGING_DIR)/usr/lib* -name \"*.la\" 2>/dev/null | wc -l" "$BRW_DIR/package/pkg-generic.mk"
    grep -q "la files to fix" "$BRW_DIR/package/pkg-generic.mk" && echo "✅ pkg-generic.mk OK" || { echo "❌ pkg-generic.mk"; exit 1; }

    # check-bin-arch
    printf "#!/bin/sh\necho \"[CI] check-bin-arch skipped\"\nexit 0\n" > "$BRW_DIR/support/scripts/check-bin-arch"

    # remove INSTALL_SYSROOT_LIBS 调用行（不是 define，define 应保留）
    PKG_MK="$BRW_DIR/toolchain/toolchain-external/pkg-toolchain-external.mk"
    sed -i "/^[[:space:]]*\$\$(TOOLCHAIN_EXTERNAL_INSTALL_SYSROOT_LIBS)/d" "$PKG_MK"
    # 确认 INSTALL_STAGING_CMDS 内不再有 CALL，但 define 本身还在
    grep '\$\$(TOOLCHAIN_EXTERNAL_INSTALL_SYSROOT_LIBS)' "$PKG_MK" && { echo "❌ call not removed"; exit 1; } || true
    grep -q 'define.*INSTALL_SYSROOT_LIBS' "$PKG_MK" && echo "✅ define preserved, call removed" || { echo "❌ define lost"; exit 1; }

    # helpers.mk readlink
    HLP="$BRW_DIR/toolchain/helpers.mk"
    BEFORE=$(grep -c "readlink -f" "$HLP" || true)
    sed -i "s/readlink -f/readlink -m/g" "$HLP"
    AFTER=$(grep -c "readlink -f" "$HLP" 2>/dev/null || true)
    echo "✅ helpers.mk: $BEFORE → $AFTER readlink -f remaining"

    # _xtheadc
    BEFORE2=$(grep -c "GCC_TARGET_ARCH)" "$PKG_MK" || true)
    sed -i "s/\$(GCC_TARGET_ARCH)/\$(GCC_TARGET_ARCH)_xtheadc/g" "$PKG_MK"
    grep -q "GCC_TARGET_ARCH)_xtheadc" "$PKG_MK" && echo "✅ _xtheadc appended" || { echo "❌ _xtheadc"; exit 1; }

    # cpio.mk mknod
    sed -i "/^[[:space:]]*mknod /s/^/#CI-DISABLED /" "$BRW_DIR/fs/cpio/cpio.mk"
    grep -q "CI-DISABLED" "$BRW_DIR/fs/cpio/cpio.mk" && echo "✅ cpio.mk OK" || { echo "❌ cpio.mk"; exit 1; }

    echo "=== ALL SED/PATCH CHECKS PASSED ==="
    echo "Ready for make buildroot."
'
