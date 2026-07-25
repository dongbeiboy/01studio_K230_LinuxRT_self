#!/bin/bash
# K230 SDK 编译修复脚本
set -e
cd /root/k230/k230_sdk
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# 安装依赖
apt-get update -qq && apt-get install -y cmake fakeroot attr 2>&1 | tail -2

# 恢复源文件
git checkout -- src/big/mpp/userapps/src/sensor/Makefile 2>/dev/null || true
git checkout -- src/big/mpp/userapps/sample/Makefile 2>/dev/null || true

# 修复 m4
M4FILE=output/k230_canmv_defconfig/little/buildroot-ext/build/host-m4-1.4.18/lib/c-stack.c
if [ -f "$M4FILE" ]; then
  sed -i 's|#elif HAVE_LIBSIGSEGV && SIGSTKSZ < 16384|#elif 0|' "$M4FILE"
  rm -f output/k230_canmv_defconfig/little/buildroot-ext/build/host-m4-1.4.18/.stamp_built
fi

# 修复 fakeroot
FKD=output/k230_canmv_defconfig/little/buildroot-ext/build/host-fakeroot-1.25.3
if [ -f "$FKD/config.h" ]; then
  sed -i 's/#define WRAP_MKNOD __xmknod$/#define WRAP_MKNOD __xmknod_old/' "$FKD/config.h" 2>/dev/null || true
  rm -f "$FKD/.stamp_built"
fi

# 修复 buildroot conf
rm -f output/k230_canmv_defconfig/little/buildroot-ext/build/buildroot-config/conf

# 修复 sensor cmake
sed -i 's|cmake -S |CC=gcc CXX=g++ cmake -DCMAKE_C_COMPILER_WORKS=1 -S |' src/big/mpp/userapps/src/sensor/Makefile

# 修复 sample cmake
sed -i 's|cmake -S |cmake -DCMAKE_C_COMPILER_WORKS=1 -DCMAKE_CXX_COMPILER_WORKS=1 -S |' src/big/mpp/userapps/sample/Makefile
sed -i 's|cmake $(MPP|cmake -DCMAKE_C_COMPILER_WORKS=1 -DCMAKE_CXX_COMPILER_WORKS=1 $(MPP|' src/big/mpp/userapps/sample/Makefile

echo "=== All fixes applied ==="

# 编译
make CONF=k230_canmv_defconfig
echo "EXIT: $?"
ls -la output/k230_canmv_defconfig/images/sysimage* 2>&1 || echo "No sysimage found"
