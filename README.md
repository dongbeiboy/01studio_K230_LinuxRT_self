# 01Studio K230 Linux+RTOS SDK

> ⚠️ **请注意：此项目由 AI 辅助开发，仅供学习使用，请不要用于生产用途** ⚠️

基于 [kendryte/k230_sdk](https://github.com/kendryte/k230_sdk) 的定制分支，专为 **01Studio K230 CanMV** 开发板（2GB LPDDR4）优化，提供 Linux + RT-Smart 双核异构系统的完整软件开发包。

[![Build & Release](https://github.com/dongbeiboy/01studio_K230_LinuxRT_self/actions/workflows/build.yml/badge.svg)](https://github.com/dongbeiboy/01studio_K230_LinuxRT_self/actions/workflows/build.yml)

---

## 目录

- [硬件规格](#硬件规格)
- [新增特性](#新增特性)
- [快速开始](#快速开始)
- [编译指南](#编译指南)
- [OTA 系统升级](#ota-系统升级)
- [A/B 分区安全升级](#ab-分区安全升级)
- [WiFi 配置](#wifi-配置)
- [项目结构](#项目结构)
- [CI/CD](#cicd)
- [已知问题与修复](#已知问题与修复)
- [参考资源](#参考资源)

---

## 硬件规格

| 项目 | 参数 |
|------|------|
| SoC | 嘉楠勘智 K230 (双核 RISC-V 64) |
| 内存 | **2GB** LPDDR4 |
| 显示 | 4-lane MIPI DSI，HX8399 面板 (800×480) |
| 存储 | MicroSD 卡 |
| 无线 | RTL8189FS WiFi |
| 接口 | USB, GPIO, MIPI CSI 摄像头 |

## 新增特性

### 🆕 相对于上游 SDK (kendryte/k230_sdk) 新增

| 特性 | 说明 |
|------|------|
| **01Studio 板级支持** | 完整 2GB LPDDR4 内存配置、U-Boot/DTS 适配、MBR 分区表 |
| **DSI 显示驱动（开发中）** | DWC MIPI DSI 控制器驱动 + HX8399 面板完整 DCS 初始化序列 |
| **屏幕终端（开发中）** | Framebuffer Console (`fbcon`) + tty1 登录终端 |
| **OTA 升级系统** | 5 种升级方式：本地文件/HTTP 下载/SD 卡/USB 自动/Web 网页上传 |
| **A/B 分区安全升级** | 双槽位无缝切换，启动 attempt 计数，失败自动回退 |
| **WiFi 联网** | RTL8189FS 驱动 + `wifi_connect` 一键联网脚本 |
| **CI/CD 流水线（开发中）** | GitHub Actions 大核/小核/RootFS 并行编译 + Release 自动发布 |
| **Ubuntu 22.04/WSL 适配** | 修复 glibc 2.35 兼容、cmake 交叉编译、VFAT 镜像构建等问题 |

### 📦 内存布局（2GB）

```
┌────────────┬──────────────┬──────────┬──────────────────┐
│   区域      │   基地址      │   大小    │   说明            │
├────────────┼──────────────┼──────────┼──────────────────┤
│ PARAM      │ 0x0000_0000  │ 1MB      │ 参数区            │
│ IPCM       │ 0x0010_0000  │ 1MB      │ 核间通信           │
│ RTT (大核)  │ 0x0020_0000  │ 766MB    │ RT-Smart 系统     │
│ Linux (小核)│ 0x3000_0000  │ 256MB    │ Linux 系统        │
│ MMZ        │ 0x4000_0000  │ 1GB      │ 多媒体共享内存      │
├────────────┼──────────────┼──────────┼──────────────────┤
│ 总计        │              │ 2GB      │                  │
└────────────┴──────────────┴──────────┴──────────────────┘
```

---

## 快速开始

### 环境要求

- WSL2 + Ubuntu 22.04 
- 磁盘空间 ≥ 20GB

### 一键编译（推荐在 WSL/原生 Linux 上裸编译）（开发中）

```bash
# 安装依赖（仅首次）
sudo apt-get install -y cmake flex bison m4 fakeroot attr zlib1g-dev \
    bc cpio unzip rsync file python3 python3-pip
pip3 install pycryptodome gmssl

# 下载源码
git clone https://github.com/dongbeiboy/01studio_K230_LinuxRT_self.git
cd k230_sdk

# 下载工具链和依赖（仅首次，耗时取决于网速）
make prepare_sourcecode

# 链接工具链
sudo ln -sf $(pwd)/toolchain /opt/toolchain

# 编译 01Studio 镜像
make CONF=k230_canmv_01studio_defconfig
```

> **注意**：WSL 环境下 PATH 包含 Windows 路径可能导致语法错误，建议使用：
> ```bash
> PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" make CONF=k230_canmv_01studio_defconfig
> ```

### 编译产物

```
output/k230_canmv_01studio_defconfig/images/
├── sysimage-sdcard.img       # SD 卡烧录镜像 (~513MB)
└── sysimage-sdcard.img.gz    # 压缩版 (~66MB)
```

### 烧录 TF 卡

```bash
# Linux
sudo dd if=sysimage-sdcard.img of=/dev/sdX bs=1M oflag=sync

# Windows: 推荐使用 Rufus (http://rufus.ie/)
```

---

## 编译指南

### 可用 defconfig

| 配置文件 | 适用板子 |
|----------|----------|
| `k230_canmv_01studio_defconfig` | **01Studio K230 CanMV (2GB)** |
| `k230_canmv_defconfig` | CanMV-K230 (原版, 512MB) |
| `k230_canmv_v2_defconfig` | CanMV-K230 V2 |
| `k230_canmv_v3_defconfig` | CanMV-K230 V3 |
| `k230d_canmv_defconfig` | K230D CanMV (PI Zero) |
| `k230_evb_defconfig` | K230 EVB 开发板 |
| `k230_canmv_lckfb_defconfig` | 立创开发板 |
| `k230_canmv_dongshanpi_defconfig` | 东山Pi |

### 增量编译

```bash
# 仅重编内核
make CONF=k230_canmv_01studio_defconfig linux-rebuild

# 仅重编 U-Boot
make CONF=k230_canmv_01studio_defconfig uboot-rebuild

# 仅重编大核 RT-Smart
make CONF=k230_canmv_01studio_defconfig rt-smart

# 仅重新打包镜像（不改源码时）
make CONF=k230_canmv_01studio_defconfig build-image
```

### A/B 双槽升级包编译

```bash
# 构建升级包（A/B 双槽）
BUILD_AB_IMAGE=1 make CONF=k230_canmv_01studio_defconfig build-image

# 一键构建烧录包 + A/B 升级包
bash tools/build_both.sh

# 构建 OTA .swu 升级包
bash tools/build_ota_package.sh
```

### Docker 编译（未验证）

```bash
docker pull ghcr.io/kendryte/k230_sdk
docker run -u root -it \
    -v $(pwd):$(pwd) \
    -v $(pwd)/toolchain:/opt/toolchain \
    -w $(pwd) \
    ghcr.io/kendryte/k230_sdk /bin/bash
# 进入容器后按上述命令编译
```

---

## OTA 系统升级

SDK 内置了完整的 OTA 升级系统，支持 **5 种升级方式**：

| 方式 | 命令 | 前提条件 |
|------|------|----------|
| 本地文件 | `ota_do local /path/to/update.swu` | 无 |
| HTTP 下载 | `ota_do http http://server/update.swu` | 已联网 |
| SD 卡自检 | `ota_do sd` | FAT 分区有 .swu 文件 |
| U 盘自检 | `ota_do usb`（或插入 U 盘自动触发） | 已启用 mdev |
| Web 网页 | `ota_do web` → 浏览器访问 `http://<ip>:9090` | 已联网 |

### 启用开机自动 Web OTA

```bash
touch /etc/ota_auto_start    # 创建标记文件
reboot                        # 重启后自动启动 Web OTA 服务
```

---

## A/B 分区安全升级

系统支持 A/B 分区无缝升级，确保升级失败时自动回退：

```
SD 卡分区布局（A/B 模式）：
┌──────────┬──────┬──────┬──────┬──────┬──────┬──────┬──────────┐
│  偏移    │ 10M  │ 30M  │ 128M │ 384M │ 404M │ 502M │ 758M     │
├──────────┼──────┼──────┼──────┼──────┼──────┼──────┼──────────┤
│ 内容     │RTT_A │Linux_A│rootfs│RTT_B │Linux_B│rootfs│ app.vfat │
│ 大小     │ 20M  │ 50M  │256M  │ 20M  │ 50M  │256M  │ 256M     │
└──────────┴──────┴──────┴──────┴──────┴──────┴──────┴──────────┘
```

- **Slot A** (p1): 当前运行分区
- **Slot B** (p2): 升级目标分区
- **app.vfat** (p3): 共享数据分区，双槽共用
- 启动 attempt 计数耗尽自动切回原槽位
- `S99boot-ok` 启动确认机制确保升级成功

### 升级流程

```bash
# 1. PC 端构建升级包
bash tools/build_both.sh

# 2. 将升级包传送到目标板
scp output/k230_canmv_01studio_defconfig/images/ota_update.swu root@<设备IP>:/tmp/

# 3. 目标板执行升级
ota_do local /tmp/ota_update.swu

# 4. 重启进入新系统
reboot
```

---

## WiFi 配置

```bash
# 扫描可用网络
wifi_connect scan

# 连接 WiFi
wifi_connect <SSID> <密码>

# 查看连接状态
wifi_connect status

# 断开 WiFi
wifi_connect off
```

---

## 项目结构

```
k230_sdk/
├── board/                      # 板级配置
│   ├── common/                  # 公共板级文件
│   │   ├── env/                 # U-Boot 环境变量
│   │   ├── gen_image_cfg/       # 镜像分区配置 (含 A/B 布局)
│   │   ├── gen_image_script/    # 镜像生成脚本
│   │   └── post_copy_rootfs/    # RootFS 叠加层 (OTA 脚本/启动脚本)
│   └── k230_canmv_dpu_depth_camera/  # 其他板级配置
├── configs/                     # defconfig 配置文件
│   ├── k230_canmv_01studio_defconfig  # ★ 01Studio 主配置
│   ├── k230_canmv_defconfig
│   └── ...
├── src/
│   ├── big/                     # 大核 (RISC-V 1.2GHz) RT-Smart 代码
│   │   ├── rt-smart/            # RT-Smart 内核
│   │   ├── mpp/                 # 多媒体处理平台
│   │   └── ai/                  # AI/KPU 相关
│   ├── little/                  # 小核 (RISC-V 0.8GHz) Linux 代码
│   │   ├── linux/               # Linux 内核
│   │   ├── uboot/               # U-Boot
│   │   ├── buildroot-ext/       # Buildroot (RootFS)
│   │   └── opensbi/             # OpenSBI
│   └── common/                  # 大小核共享代码
├── tools/                       # 工具集
│   ├── build_both.sh            # 一键构建 (烧录包 + A/B 升级包)
│   ├── build_ota_package.sh     # OTA 升级包构建
│   ├── ota_ab_upgrade.sh        # 目标板 A/B 升级脚本
│   ├── fix_and_build.sh         # 编译修复脚本
│   ├── genimage                 # 镜像生成工具
│   └── kconfig/                 # Kconfig 配置工具
├── .github/workflows/build.yml  # CI/CD 流水线
├── Makefile                     # 顶层 Makefile
├── Kconfig                      # 顶层 Kconfig
└── jn_readme.md                 # 上游 SDK 原始 README
```

---

## CI/CD

本项目配置了 GitHub Actions 自动化流水线（`.github/workflows/build.yml`）：

- **PR / Push to main**：轻量门禁（defconfig 校验 + ShellCheck）
- **Tag push (v\*)**：全量并行编译 + Release 发布
  - 大核 (RTT + MPP + OpenSBI)：约 20 分钟
  - 小核 (Linux + U-Boot + OpenSBI)：约 30 分钟
  - RootFS (Buildroot)：约 20 分钟
  - 三路并行 → 总耗时约 1.1 小时

---

## 已知问题与修复

### glibc 2.35 兼容性（Ubuntu 22.04+）

| 问题 | 修复方式 |
|------|----------|
| `host-m4` SIGSTKSZ 编译错误 | `sed -i 's/#elif HAVE_LIBSIGSEGV && SIGSTKSZ < 16384/#elif 0/' c-stack.c` |
| `host-fakeroot` WRAP_MKNOD 错误 | `sed -i 's/#define WRAP_MKNOD __xmknod$/#define WRAP_MKNOD __xmknod_old/' config.h` |

### cmake 交叉编译

`k230dwmapgen` 工具需要修复 cmake 调用，指定 host 编译器：

```bash
sed -i 's|cmake -S |CC=gcc CXX=g++ cmake -DCMAKE_C_COMPILER_WORKS=1 -S |' \
    src/big/mpp/userapps/src/sensor/Makefile
```

### VFAT 镜像构建

genimage 的 mcopy 在 256MB VFAT 分区上可能失败，已改为手动 `mount + cp` 方式构建 `app.vfat`。

---

## 更多信息

- 📘 [嘉楠勘智原版 README](./jn_readme.md)
- 📘 [编译备忘 (内部)](./memories/repo/compile-notes.md)
- 📘 [内存配置详解 (内部)](./memories/repo/memory.md)
- 🔗 [上游 SDK](https://github.com/kendryte/k230_sdk)
- 🔗 [K230 文档](https://github.com/kendryte/k230_docs)
- 🔗 [嘉楠开发者社区](https://developer.canaan-creative.com/)

---

## License

本项目沿用上游 [kendryte/k230_sdk](https://github.com/kendryte/k230_sdk) 的 LICENSE。详见 [LICENSE](./LICENSE) 文件。
