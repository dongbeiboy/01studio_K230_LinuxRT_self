#!/bin/bash
# CI ccache wrapper 安装
# 用法: bash .github/scripts/setup-ccache.sh <CCACHE_DIR> <TC_BIN> <PREFIX>
set -euo pipefail
CCACHE_DIR="$1"
TC_BIN="$2"
PREFIX="$3"
echo "CCACHE_DIR=$CCACHE_DIR" >> "$GITHUB_ENV"
echo "CCACHE_COMPILERCHECK=content" >> "$GITHUB_ENV"
echo "CCACHE_MAXSIZE=2G" >> "$GITHUB_ENV"
echo "CCACHE_COMPRESS=1" >> "$GITHUB_ENV"
for prog in gcc g++ cc cpp; do
  BIN="$TC_BIN/${PREFIX}-$prog"
  if [ -f "$BIN" ] && [ ! -f "$BIN.real" ]; then
    sudo mv "$BIN" "$BIN.real"
    printf '#!/bin/sh\nexec ccache %s "$@"\n' "$BIN.real" | sudo tee "$BIN" > /dev/null
    sudo chmod +x "$BIN"
  fi
done
