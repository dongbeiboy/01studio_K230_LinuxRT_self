# 01Studio K230 Linux+RTOS SDK

> ⚠️ **请注意：此项目由 AI 辅助开发，仅供学习使用，请不要用于生产用途** ⚠️

基于 [kendryte/k230_sdk](https://github.com/kendryte/k230_sdk) 的个人分支，专为 **01Studio K230 CanMV** 开发板（2GB LPDDR4）优化，支持 A/B 分区 OTA 安全升级。

[![Build & Release](https://github.com/dongbeiboy/01studio_K230_LinuxRT_self/actions/workflows/build.yml/badge.svg)](https://github.com/dongbeiboy/01studio_K230_LinuxRT_self/actions/workflows/build.yml)

---

## 📚 文档

**完整文档请访问 [Wiki](https://github.com/dongbeiboy/01studio_K230_LinuxRT_self/wiki)**：

| 页面 | 说明 |
|------|------|
| [编译与烧录指南](https://github.com/dongbeiboy/01studio_K230_LinuxRT_self/wiki/编译与烧录指南) | 环境搭建、增量编译、烧录方法 |
| [OTA 升级与 A-B 分区](https://github.com/dongbeiboy/01studio_K230_LinuxRT_self/wiki/OTA-升级与-A-B-分区) | 5 种升级方式、安全回退机制 |
| [WiFi 联网配置](https://github.com/dongbeiboy/01studio_K230_LinuxRT_self/wiki/WiFi-联网配置) | RTL8189FS 一键联网 |
| [项目结构](https://github.com/dongbeiboy/01studio_K230_LinuxRT_self/wiki/项目结构) | 源码树与关键文件说明 |
| [CI/CD 流水线](https://github.com/dongbeiboy/01studio_K230_LinuxRT_self/wiki/CI-CD-流水线) | GitHub Actions 自动编译发布 |
| [已知问题与修复](https://github.com/dongbeiboy/01studio_K230_LinuxRT_self/wiki/已知问题与修复) | glibc/cmake/VFAT 常见问题 |

---

## ⚡ 快速开始

### 环境要求

- WSL2 + Ubuntu 22.04（或原生 Linux）
- 磁盘空间 ≥ 30GB

### 一键编译

```bash
# 安装依赖（仅首次）
sudo apt-get install -y cmake flex bison m4 fakeroot attr zlib1g-dev \
    bc cpio unzip rsync file python3 python3-pip
pip3 install pycryptodome gmssl

# 克隆仓库
git clone https://github.com/dongbeiboy/01studio_K230_LinuxRT_self.git
cd k230_sdk

# 下载工具链和依赖（仅首次）
make prepare_sourcecode
sudo ln -sf $(pwd)/toolchain /opt/toolchain

# 一键编译（A/B 镜像 + OTA 包，~90 分钟）
bash build_all.sh

# 选项：
bash build_all.sh --clean              # 清空缓存全新编译
bash build_all.sh --ab-only            # 只打包镜像（跳过编译）
bash build_all.sh --rootfs-only        # 只编译 rootfs + 打包
bash build_all.sh k230_evb_defconfig   # 指定 defconfig
```

### 编译产物

```
output/k230_canmv_01studio_defconfig/images/
├── sysimage-sdcard-ab.img.gz       # A/B 双槽烧录镜像 (~126M)
├── sysimage-sdcard-ab.img          # 解压后 (1014M, sparse 279M)
└── k230_ota_ab_YYYYMMDD.tar.gz     # OTA 升级包 (~49M)
```

### 烧录 TF 卡

推荐使用 **balenaEtcher**（跨平台，免费）：

1. 下载 [balenaEtcher](https://etcher.io)
2. 选择 `sysimage-sdcard-ab.img.gz`（**无需解压**）
3. 选择 SD 卡 → 点击 Flash

> Etcher 自动识别稀疏镜像，只写有效数据 (~279M)，烧录快速。
>
> **不推荐** `gunzip | dd`：解压后镜像 1014M 全写 SD 卡，比 Etcher 慢 4 倍以上。
> 如果必须用 `dd`，加 `conv=sparse`：
> ```bash
> gunzip -c sysimage-sdcard-ab.img.gz | sudo dd of=/dev/sdX bs=1M conv=sparse status=progress
> ```

---

## 🆕 相对上游 SDK 新增特性

| 特性 | 说明 |
|------|------|
| **01Studio 板级支持** | 2GB LPDDR4 内存配置、U-Boot/DTS 适配、MBR 分区表 |
| **OTA + A/B 分区** | 5 种升级方式，双槽位无缝切换，失败自动回退 |
| **WiFi 联网** | RTL8189FS 驱动 + `wifi_connect` 一键联网 |
| **CI/CD 流水线** | GitHub Actions 并行编译 + Release 自动发布 |
| **Ubuntu 22.04/WSL 适配** | 修复 glibc 2.35、cmake 交叉编译、VFAT 构建等问题 |
| **DSI 显示驱动（开发中）** | DWC MIPI DSI + HX8399 面板 |

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

## 📖 更多信息

- 📘 [项目 Wiki](https://github.com/dongbeiboy/01studio_K230_LinuxRT_self/wiki) — 完整文档
- 📘 [嘉楠勘智原版 README](./jn_readme.md)
- 📘 [编译备忘 (内部)](./memories/repo/compile-notes.md)
- 📘 [内存配置详解 (内部)](./memories/repo/memory.md)
- 🔗 [上游 SDK](https://github.com/kendryte/k230_sdk)
- 🔗 [K230 文档](https://github.com/kendryte/k230_docs)
- 🔗 [嘉楠开发者社区](https://developer.canaan-creative.com/)

---

## 已知问题

- 屏幕不亮

---

## License

本项目沿用上游 [kendryte/k230_sdk](https://github.com/kendryte/k230_sdk) 的 LICENSE。详见 [LICENSE](./LICENSE) 文件。
