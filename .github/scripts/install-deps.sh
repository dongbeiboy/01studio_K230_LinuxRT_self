#!/bin/bash
# CI 系统依赖安装
# 用法: bash .github/scripts/install-deps.sh [extra-packages...]
set -euo pipefail
sudo dpkg --add-architecture i386
sudo apt-get update -qq
sudo apt-get install -y -qq --no-install-recommends \
  cmake flex bison m4 fakeroot attr zlib1g-dev \
  bc cpio unzip rsync file make binutils build-essential \
  gcc g++ bash patch gzip bzip2 perl tar dosfstools mtools \
  autoconf automake pkg-config libc6-dev-i386 libncurses5:i386 \
  libssl-dev libncurses5-dev libconfuse2 libconfuse-dev \
  python3 python3-pip python-is-python3 scons wget curl ccache
pip3 install pycryptodome gmssl
