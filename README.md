

# ailg666/xy

## 📖 项目简介
本仓库（`ailg666/xy`）是一套面向 NAS、Docker 环境及媒体服务器（G-Box / 小雅生态）的自动化维护与优化工具集。包含环境初始化、云盘清理、Docker 镜像加速、硬盘智能休眠、元数据更新等实用 Shell 脚本，旨在简化部署流程、提升网络稳定性并延长硬件寿命。所有脚本均托管于 GitHub Pages（`gbox.ggbond.org`），支持远程一键拉取执行。

## 📦 核心脚本说明

| 脚本名称 | 功能描述 |
|---|---|
| `ab_casaos.sh` | 系统环境初始化。设置时区为 `Asia/Shanghai`，替换清华软件源，自动安装 Docker 与 CasaOS。 |
| `ali_clear_ailg.sh` | 阿里云盘转存文件清理守护脚本。支持自动刷新 Token、定时清理过期文件、管理 Crontab 及同步 Docker 镜像 SHA。 |
| `cd2.sh` | CloudDrive2 Docker 版安装/卸载脚本。自动处理 FUSE3 依赖、共享挂载点配置，支持跨平台（Linux/macOS/群晖）开机自启。 |
| `docker_pull.sh` / `docker_pull_new.sh` | 智能 Docker 镜像拉取工具。内置多节点测速，自动选择最优镜像源，拉取失败自动重试与切换。 |
| `fix_docker.sh` | Docker 镜像源配置修复脚本。自动检测 `daemon.json`，备份原配置，注入/清除镜像代理并验证网络连通性。 |
| `hd_sleep.sh` | 工业级硬盘智能休眠守护进程。基于 `/proc/diskstats` IO 监控与动态超时策略，支持防误唤醒、每日唤醒次数限制及熔断保护。 |
| `update_meta_jf.sh` | 媒体库刮削元数据批量下载与解压工具。基于 `aria2c` 与 `7z` 实现断点续传与多线程解压，适用于 Jellyfin/Emby。 |
| `stun_gbox.sh` | G-Box 面板 API 交互脚本。用于更新节点配置、域名绑定与面板服务状态同步，内置依赖自动安装（`jq`/`ping`）。 |

## 🚀 安装与使用

### 前置要求
- Linux/Unix 环境（推荐 Debian/Ubuntu/Alpine/群晖 DSM/Apple Silicon）
- 具备 `root` 或 `sudo` 权限
- 已安装基础工具链（部分脚本会自动检测缺失命令并尝试安装）
- 网络环境可访问 GitHub / 阿里云盘 API / Docker Hub 镜像源

### 一键安装主菜单
在目标设备的 SSH 终端中执行以下命令，即可进入 G-Box 主安装菜单（根据引导完成各项安装）：
```bash
bash -c "$(curl -sSLf https://ailg.ggbond.org/xy_install.sh)"
```
*备用加速地址：*
```bash
bash -c "$(curl -sSLf https://gbox.ggbond.org/xy_install.sh)"
bash -c "$(curl -sSLf https://xy.ggbond.org/xy/xy_install.sh)"
```

### 独立脚本使用示例
各工具脚本均可独立下载执行，典型用法如下：

**1. 环境初始化与 CasaOS 安装**
```bash
bash -c "$(curl -sSLf https://ailg.ggbond.org/ab_casaos.sh)"
```

**2. 智能拉取 Docker 镜像**
```bash
# 交互式模式（自动测速选源）
bash docker_pull.sh
# 直接指定镜像与配置目录
bash docker_pull.sh ailg/alist:latest /etc/xiaoya
```

**3. 安装/卸载 CloudDrive2**
```bash
bash cd2.sh                  # 安装（提示输入目录与端口）
bash cd2.sh uninstall        # 卸载（可选保留配置文件）
```

**4. 配置硬盘智能休眠**
```bash
# 传入目标硬盘 ID（支持多盘参数传递）
bash hd_sleep.sh "/dev/disk/by-id/ata-WDC_WD20SPZX_XXX" "/dev/disk/by-id/ata-Seagate_XXX"
# 远程执行示例
curl -sSLf https://ailg.ggbond.org/hd_sleep.sh | bash -s "/dev/disk/by-id/ata-XXX"
```

**5. 修复 Docker 镜像源**
```bash
bash fix_docker.sh
# 脚本会提示是否使用自定义镜像源，自动备份/恢复 daemon.json 并重载 Docker 服务
```

## ⚠️ 注意事项
1. 本仓库脚本均为作者个人自用维护，**不保证兼容所有系统版本与硬件环境**，请勿直接用于关键生产环境。
2. 运行脚本前建议备份重要数据及配置文件（如 `/etc/docker/daemon.json`、云盘 Token 文件等）。
3. 阿里云盘清理脚本 (`ali_clear_ailg.sh`) 依赖 `/data/` 目录下的配置文件（`mytoken.txt`, `temp_transfer_folder_id.txt`, `folder_type.txt` 等），请确保路径与内容正确。
4. 部分操作涉及系统底层挂载、进程守护与网络配置，请确保具备 `root` 权限。运行中如有疑虑可随时按 `Ctrl+C` 终止。

## 💬 交流与支持
- 📺 视频教程：[G-Box 保镖级教程](https://youtu.be/hYwCxJqChUw) ｜ [115风控与Emby速装](https://b23.tv/ewhi6pF)
- 💬 技术交流群：[Telegram 群](https://t.me/ailg666) ｜ 微信：`ailg_666`
- ☕ 喜欢本项目？欢迎请作者喝杯咖啡：[赞赏支持](https://ailg.ggbond.org/3q.jpg)

> **免责声明**：本项目仅供技术交流与学习使用。任何因使用本脚本导致的系统异常、服务中断或数据丢失，作者不承担任何责任。请在运行前仔细阅读脚本内容，按需自行修改参数。
