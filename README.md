# Mihomo + Zashboard Linux 一键安装脚本

一个面向 Linux 服务器的 Mihomo（Clash Meta）+ Zashboard 一键安装项目。安装后会自动下载匹配当前 CPU 架构的 Mihomo 内核，导入订阅，配置 Zashboard 面板，并注册 systemd 开机自启服务。

> 适合 Ubuntu / Debian / CentOS / Rocky / AlmaLinux / Fedora / Arch / Alpine 等常见 Linux 发行版。当前脚本主要针对 systemd 系统。

## 一键安装

国内网络建议使用 GitHub 加速地址拉取安装脚本。下面 3 个任选一个，仓库用户名已配置为 `jiumian8`。

> 为避免 GitHub / 加速源缓存到 Windows CRLF 换行版本，下面命令都加了 `tr -d '\r'`，会在执行前自动清理回车符。

### 方式 1：IPv4 优选加速

```bash
bash <(curl -fsSL 'https://v4.gh-proxy.org/https://raw.githubusercontent.com/jiumian8/clash-for-linux-install/main/install.sh?cache=lf' | tr -d '\r')
```

### 方式 2：IPv6 / IPv4 优选加速

```bash
bash <(curl -fsSL 'https://v6.gh-proxy.org/https://raw.githubusercontent.com/jiumian8/clash-for-linux-install/main/install.sh?cache=lf' | tr -d '\r')
```

### 方式 3：Fastly CDN 节点加速

```bash
bash <(curl -fsSL 'https://cdn.gh-proxy.org/https://raw.githubusercontent.com/jiumian8/clash-for-linux-install/main/install.sh?cache=lf' | tr -d '\r')
```

也可以直连 GitHub：

```bash
bash <(curl -fsSL 'https://raw.githubusercontent.com/jiumian8/clash-for-linux-install/main/install.sh?cache=lf' | tr -d '\r')
```

如果你是先 clone 本仓库，也可以执行：

```bash
git clone https://github.com/jiumian8/clash-for-linux-install.git
cd clash-for-linux-install
sudo bash install.sh
```

如果仍然报 CRLF 相关错误，用下面的分步命令排查：

```bash
curl -fsSL 'https://v4.gh-proxy.org/https://raw.githubusercontent.com/jiumian8/clash-for-linux-install/main/install.sh?cache=lf' -o install.sh
tr -d '\r' < install.sh > install.lf.sh
bash install.lf.sh
```

安装开始后，脚本会让用户选择 GitHub 加速源，用于后续下载 Mihomo 内核、Zashboard 面板和升级内核：

```text
请选择 GitHub 加速源（用于下载 Mihomo / Zashboard / 后续升级）：
1) 优选加速服务器，仅支持 IPv4 网络智能解析：https://v4.gh-proxy.org/
2) 优选加速服务器，支持 IPv6/IPv4 网络智能解析：https://v6.gh-proxy.org/
3) Fastly CDN 节点加速：https://cdn.gh-proxy.org/
4) 不使用加速，直连 GitHub
请选择 [1-4，默认 1]：
```

如需无人值守安装，也可以用环境变量提前指定加速源：

```bash
GH_PROXY=https://v4.gh-proxy.org bash install.sh
```

安装过程会要求输入订阅链接：

```text
请输入订阅链接 URL（必填）：https://example.com/subscription/url
```

安装完成后会输出：

- Zashboard 访问地址
- External Controller 地址
- 面板密钥 Secret
- 自动分配的代理端口

示例：

```text
Zashboard 访问地址：http://服务器IP:9090/ui/
密钥：xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
SSH 中输入 clash 可打开管理菜单。
```

## 功能特性

| 功能 | 说明 |
| --- | --- |
| 自动识别系统架构 | 根据 `uname -m` 自动识别 `amd64`、`arm64`、`armv7`、`armv6`、`386` 并下载对应 Mihomo 内核 |
| GitHub 加速源选择 | 安装时可选择 `v4.gh-proxy.org`、`v6.gh-proxy.org`、`cdn.gh-proxy.org` 或直连 GitHub，避免直连 GitHub 不稳定 |
| 端口自动检测与分配 | 默认从 7890、7891、7892、9090 起检测空闲端口，避免和已有服务冲突 |
| TUN 模式 | 支持在菜单中开启 / 关闭 TUN，用于透明代理、网关接管等场景 |
| 首次安装订阅导入 | 第一次安装必须输入订阅链接，并自动拉取订阅配置 |
| 开机自启 | 自动创建并启用 `mihomo.service` |
| Zashboard 面板 | 自动下载 Zashboard 并配置为 Mihomo 外部 UI |
| SSH 菜单管理 | SSH 输入 `clash` 即可进入中文管理菜单 |
| 完整卸载 | 卸载时清理 systemd 服务、二进制、配置、日志、菜单命令 |



## 离线内核包说明：避免 GitHub API 403

脚本会优先从本仓库的 `archives/` 目录下载离线包，避免安装时访问 `api.github.com` 导致 403。

请至少准备当前服务器架构对应的 Mihomo 内核包：

| 服务器架构 | 推荐文件名 | 放置路径 |
| --- | --- | --- |
| `amd64` / `x86_64` | `mihomo-linux-amd64-compatible.gz` | `archives/mihomo-linux-amd64-compatible.gz` |
| `amd64` / `x86_64` | `mihomo-linux-amd64.gz` | `archives/mihomo-linux-amd64.gz` |
| `arm64` / `aarch64` | `mihomo-linux-arm64.gz` | `archives/mihomo-linux-arm64.gz` |
| `armv7` | `mihomo-linux-armv7.gz` | `archives/mihomo-linux-armv7.gz` |
| `armv6` | `mihomo-linux-armv6.gz` | `archives/mihomo-linux-armv6.gz` |
| `386` / `i386` / `i686` | `mihomo-linux-386.gz` | `archives/mihomo-linux-386.gz` |

Zashboard 离线包建议放在：

```text
archives/dist.zip
```

本仓库已经带有 `archives/dist.zip` 时，安装脚本会优先使用它。

如果你不想把 Mihomo 内核包放进仓库，也可以安装时手动指定下载地址：

```bash
MIHOMO_URL='https://你的镜像地址/mihomo-linux-amd64-compatible.gz' \
bash <(curl -fsSL 'https://v4.gh-proxy.org/https://raw.githubusercontent.com/jiumian8/clash-for-linux-install/main/install.sh?cache=offline' | tr -d '\r')
```

## SSH 菜单使用方法

安装完成后，在 SSH 中输入：

```bash
clash
```

会看到菜单：

```text
========== Mihomo + Zashboard 菜单 ==========
1) 开启代理
2) 关闭代理
3) 重新导入订阅
4) 设置/查看密钥
5) 开启/关闭 TUN 模式
6) Mixin 配置管理（端口等）
7) 升级当前或指定内核
8) 诊断功能
9) 显示日志
10) 重启程序
11) 卸载程序
12) 显示 Zashboard 地址和密钥
0) 退出
```

也支持直接使用子命令：

```bash
sudo clash on          # 开启代理
sudo clash off         # 关闭代理
sudo clash sub         # 重新导入订阅
sudo clash secret      # 查看/重置密钥
sudo clash tun         # 开启/关闭 TUN 模式
sudo clash mixin       # 修改端口等 Mixin 配置
sudo clash upgrade     # 升级当前或指定 Mihomo 内核
clash doctor           # 诊断服务、端口、版本、日志
clash log              # 实时显示日志
sudo clash restart     # 重启 Mihomo
sudo clash uninstall   # 卸载并清理
clash ui               # 显示 Zashboard 地址和密钥
```

## 默认安装位置

| 路径 | 用途 |
| --- | --- |
| `/opt/mihomo/bin/mihomo` | Mihomo 内核 |
| `/opt/mihomo/ui` | Zashboard 静态面板文件 |
| `/etc/mihomo/env` | 订阅链接、GitHub 加速源、端口、密钥等运行变量 |
| `/etc/mihomo/mixin.yaml` | Mixin 配置，管理端口、TUN、DNS、面板等 |
| `/etc/mihomo/subscription.yaml` | 订阅拉取后的原始配置 |
| `/etc/mihomo/runtime.yaml` | 实际运行配置，由清理后的订阅配置 + `mixin.yaml` 合并生成 |
| `/etc/systemd/system/mihomo.service` | systemd 服务 |
| `/usr/local/bin/clash` | SSH 管理菜单命令 |
| `/var/log/mihomo.log` | 运行日志 |

## 端口说明

脚本默认会自动寻找空闲端口：

| 默认起始端口 | 用途 |
| --- | --- |
| `7890` | mixed-port |
| `7891` | HTTP 代理端口 |
| `7892` | SOCKS 代理端口 |
| `9090` | External Controller / Zashboard 控制端口 |

如果端口被占用，会自动向后寻找可用端口，例如 `7893`、`7894` 等。

后续可通过菜单修改：

```bash
sudo clash mixin
```

输入 `auto` 可重新自动分配端口。

## TUN 模式说明

TUN 模式适合透明代理、旁路由、网关接管等场景。开启方式：

```bash
sudo clash tun
```

脚本会修改 `/etc/mihomo/mixin.yaml`：

```yaml
tun:
  enable: true
  stack: mixed
  auto-route: true
  auto-detect-interface: true
  dns-hijack:
    - any:53
```

> 注意：TUN 模式需要 `CAP_NET_ADMIN` 权限。脚本的 systemd 服务已默认配置相关 capability。

## 重新导入订阅

```bash
sudo clash sub
```

可以直接回车使用当前订阅链接，也可以输入新的订阅链接。

导入后会自动合并配置并重启服务。

## 查看 Zashboard 地址和密钥

```bash
clash ui
```

输出类似：

```text
Zashboard: http://服务器IP:9090/ui/
控制器: http://服务器IP:9090
密钥: xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

如果服务器有安全组、防火墙，需要放行 External Controller 端口，例如默认 `9090` 或脚本自动分配出来的端口。

## 升级 Mihomo 内核

升级命令会自动沿用首次安装时选择并保存到 `/etc/mihomo/env` 的 `GH_PROXY` 加速源。

自动升级到最新 release：

```bash
sudo clash upgrade
```

也可以在提示时填入指定 Mihomo `.gz` 下载地址，用于安装指定版本内核。

## 诊断与日志

诊断：

```bash
clash doctor
```

实时日志：

```bash
clash log
```

手动查看 systemd 状态：

```bash
systemctl status mihomo --no-pager
journalctl -u mihomo -e --no-pager
```

## 卸载

```bash
sudo clash uninstall
```

卸载会清理：

- `mihomo.service`
- `/opt/mihomo`
- `/etc/mihomo`
- `/usr/local/bin/clash`
- `/var/log/mihomo.log`

## 常见问题

### 1. Zashboard 打不开

检查：

```bash
clash ui
clash doctor
```

确认服务器防火墙 / 云厂商安全组已放行控制端口。

### 2. 订阅导入失败

检查订阅链接是否能在服务器上访问：

```bash
curl -I '你的订阅链接'
```

如果订阅链接需要特殊 UA 或后端转换，请先使用订阅转换服务生成 Clash/Mihomo 可用 YAML。

### 3. TUN 开启后网络异常

先关闭 TUN：

```bash
sudo clash tun
```

选择关闭，然后查看日志：

```bash
clash doctor
```

不同发行版、容器环境、VPS 内核能力对 TUN 支持不同。容器内运行通常需要额外开启 `/dev/net/tun` 与 `NET_ADMIN`。

## GitHub 加速源说明

脚本内所有 GitHub 相关下载都会经过所选加速源，包括：

- GitHub API：获取 Mihomo / Zashboard 最新 release
- GitHub release asset：下载 Mihomo 内核压缩包
- Zashboard release / gh-pages zip
- 后续 `sudo clash upgrade` 内核升级

可选加速源：

| 编号 | 地址 | 说明 |
| --- | --- | --- |
| `1` | `https://v4.gh-proxy.org/` | 优选加速服务器，仅支持 IPv4 网络智能解析 |
| `2` | `https://v6.gh-proxy.org/` | 优选加速服务器，支持 IPv6/IPv4 网络智能解析 |
| `3` | `https://cdn.gh-proxy.org/` | Fastly CDN 节点加速 |
| `4` | 空 | 不使用加速，直连 GitHub |

## 变量覆盖

安装时可通过环境变量覆盖默认行为：

```bash
MIHOMO_REPO=MetaCubeX/mihomo \
ZASHBOARD_REPO=Zephyruso/zashboard \
INSTALL_DIR=/opt/mihomo \
CONFIG_DIR=/etc/mihomo \
SERVICE_NAME=mihomo \
GH_PROXY=https://v4.gh-proxy.org \
sudo -E bash install.sh
```

## 免责声明

本项目只负责安装和管理 Mihomo + Zashboard。请确保你的使用方式符合当地法律法规和服务条款。
