#!/bin/bash
# partition_layout.sh — A/B 分区布局单一真相来源
# 所有 U-Boot、genimage、系统脚本从此文件获取偏移量
#
# 使用方法:
#   source partition_layout.sh
#   echo $SLOT_A_RTT_OFFSET       # 10M
#   echo $((SLOT_B_ROOTFS_OFFSET))# 502M
#
# 用于生成 C 头文件:
#   source partition_layout.sh
#   echo "#define SLOT_A_RTT_SEC $((SLOT_A_RTT_OFFSET/512))"

# ============================================
# Slot A 偏移（与现有布局兼容）
# ============================================
SLOT_A_RTT_OFFSET=10M
SLOT_A_LINUX_OFFSET=30M
SLOT_A_ROOTFS_OFFSET=128M

# ============================================
# Slot B 偏移（新增）
# ============================================
SLOT_B_RTT_OFFSET=384M
SLOT_B_LINUX_OFFSET=404M
SLOT_B_ROOTFS_OFFSET=502M

# ============================================
# App 分区偏移
# ============================================
APP_OFFSET=758M
APP_SIZE=256M

# ============================================
# 各分区大小
# ============================================
RTT_SLOT_SIZE=20M
LINUX_SLOT_SIZE=50M
ROOTFS_SLOT_SIZE=256M

# ============================================
# U-Boot env 偏移与大小
# ============================================
# 主副本
ENV_OFFSET=0x1e0000
ENV_SIZE=0x10000     # 64K
# 冗余副本
ENV_REDUND_OFFSET=0x1f0000
# genimage 分配的总大小
ENV_TOTAL_SIZE=0x20000  # 128K

# ============================================
# 辅助函数：转换为扇区号（512B/扇区）
# ============================================
offset_to_sector() {
    local val="$1"
    val="${val%M}"
    echo $((val * 1024 * 1024 / 512))
}

size_to_sector() {
    local val="$1"
    val="${val%M}"
    echo $((val * 1024 * 1024 / 512))
}

# 输出全部扇区偏移（用于生成 C 头文件）
print_c_defines() {
    echo "// Auto-generated from partition_layout.sh — DO NOT EDIT"
    echo "#define SLOT_A_RTT_SEC     $(offset_to_sector $SLOT_A_RTT_OFFSET)"
    echo "#define SLOT_A_LINUX_SEC   $(offset_to_sector $SLOT_A_LINUX_OFFSET)"
    echo "#define SLOT_A_ROOTFS_SEC  $(offset_to_sector $SLOT_A_ROOTFS_OFFSET)"
    echo "#define SLOT_B_RTT_SEC     $(offset_to_sector $SLOT_B_RTT_OFFSET)"
    echo "#define SLOT_B_LINUX_SEC   $(offset_to_sector $SLOT_B_LINUX_OFFSET)"
    echo "#define SLOT_B_ROOTFS_SEC  $(offset_to_sector $SLOT_B_ROOTFS_OFFSET)"
    echo "#define APP_OFFSET_SEC     $(offset_to_sector $APP_OFFSET)"
    echo ""
    echo "// 分区大小（扇区）"
    echo "#define RTT_SLOT_SEC       $(size_to_sector $RTT_SLOT_SIZE)"
    echo "#define LINUX_SLOT_SEC     $(size_to_sector $LINUX_SLOT_SIZE)"
    echo "#define ROOTFS_SLOT_SEC    $(size_to_sector $ROOTFS_SLOT_SIZE)"
}

# 输出全部偏移（用于 shell 脚本引用）
print_sh_defines() {
    echo "# Auto-generated from partition_layout.sh — DO NOT EDIT"
    echo "SLOT_A_RTT_SEC=\$(offset_to_sector \$SLOT_A_RTT_OFFSET)"
    echo "SLOT_A_LINUX_SEC=\$(offset_to_sector \$SLOT_A_LINUX_OFFSET)"
    echo "SLOT_A_ROOTFS_SEC=\$(offset_to_sector \$SLOT_A_ROOTFS_OFFSET)"
    echo "SLOT_B_RTT_SEC=\$(offset_to_sector \$SLOT_B_RTT_OFFSET)"
    echo "SLOT_B_LINUX_SEC=\$(offset_to_sector \$SLOT_B_LINUX_OFFSET)"
    echo "SLOT_B_ROOTFS_SEC=\$(offset_to_sector \$SLOT_B_ROOTFS_OFFSET)"
}

# 检查 Slot A 是否与现有布局一致
check_consistency() {
    local err=0
    # 现有 RTT 偏移 = 10M
    [ "$SLOT_A_RTT_OFFSET" = "10M" ]   || { echo "ERROR: SLOT_A_RTT_OFFSET != 10M"; err=1; }
    # 现有 Linux 偏移 = 30M
    [ "$SLOT_A_LINUX_OFFSET" = "30M" ] || { echo "ERROR: SLOT_A_LINUX_OFFSET != 30M"; err=1; }
    # 现有 rootfs 偏移 = 128M
    [ "$SLOT_A_ROOTFS_OFFSET" = "128M" ] || { echo "ERROR: SLOT_A_ROOTFS_OFFSET != 128M"; err=1; }
    # env 偏移 = 0x1e0000 (1920K)
    [ "$ENV_OFFSET" = "0x1e0000" ]     || { echo "ERROR: ENV_OFFSET != 0x1e0000"; err=1; }
    # env 冗余 = 0x1f0000 (1984K)
    [ "$ENV_REDUND_OFFSET" = "0x1f0000" ] || { echo "ERROR: ENV_REDUND_OFFSET != 0x1f0000"; err=1; }

    if [ "$err" -eq 0 ]; then
        echo "partition_layout.sh: Slot A offsets consistent with existing layout ✓"
    fi
    return $err
}

# 如果直接执行此脚本，输出 C 头文件内容并检查一致性
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    print_c_defines
    echo ""
    echo "// === Consistency check ==="
    check_consistency
fi
