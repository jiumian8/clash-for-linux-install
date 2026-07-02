#!/usr/bin/env bash
set -Eeuo pipefail

# Mihomo + Zashboard one-click installer for Linux
# Project: clash-for-linux-install

MIHOMO_REPO="${MIHOMO_REPO:-MetaCubeX/mihomo}"
ZASHBOARD_REPO="${ZASHBOARD_REPO:-Zephyruso/zashboard}"
PROJECT_REPO="${PROJECT_REPO:-jiumian8/clash-for-linux-install}"
PROJECT_BRANCH="${PROJECT_BRANCH:-main}"
MIHOMO_URL="${MIHOMO_URL:-}"
INSTALL_DIR="${INSTALL_DIR:-/opt/mihomo}"
CONFIG_DIR="${CONFIG_DIR:-/etc/mihomo}"
BIN_DIR="${BIN_DIR:-/usr/local/bin}"
SERVICE_NAME="${SERVICE_NAME:-mihomo}"
RUN_USER="${RUN_USER:-root}"
GH_PROXY="${GH_PROXY:-}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

info(){ echo -e "${BLUE}[INFO]${NC} $*"; }
success(){ echo -e "${GREEN}[OK]${NC} $*"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $*"; }
err(){ echo -e "${RED}[ERR]${NC} $*" >&2; }
need_root(){ [[ ${EUID:-$(id -u)} -eq 0 ]] || { err "请使用 root 运行：sudo bash install.sh"; exit 1; }; }
has(){ command -v "$1" >/dev/null 2>&1; }
rand_secret(){ tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32 || date +%s%N | sha256sum | cut -c1-32; }

choose_github_proxy(){
  if [[ -n "${GH_PROXY:-}" ]]; then
    GH_PROXY="${GH_PROXY%/}"
    info "使用环境变量指定的 GitHub 加速源：$GH_PROXY"
    return 0
  fi
  echo
  echo "请选择 GitHub 加速源（用于下载 Mihomo / Zashboard / 后续升级）："
  echo "1) 优选加速服务器，仅支持 IPv4 网络智能解析：https://v4.gh-proxy.org/"
  echo "2) 优选加速服务器，支持 IPv6/IPv4 网络智能解析：https://v6.gh-proxy.org/"
  echo "3) Fastly CDN 节点加速：https://cdn.gh-proxy.org/"
  echo "4) 不使用加速，直连 GitHub"
  read -r -p "请选择 [1-4，默认 1]：" proxy_choice
  case "${proxy_choice:-1}" in
    1) GH_PROXY="https://v4.gh-proxy.org" ;;
    2) GH_PROXY="https://v6.gh-proxy.org" ;;
    3) GH_PROXY="https://cdn.gh-proxy.org" ;;
    4) GH_PROXY="" ;;
    *) warn "无效选择，默认使用 IPv4 优选加速源"; GH_PROXY="https://v4.gh-proxy.org" ;;
  esac
  [[ -n "$GH_PROXY" ]] && info "已选择 GitHub 加速源：$GH_PROXY" || warn "已选择直连 GitHub"
}

is_github_url(){ [[ "$1" =~ ^https://(api\.)?github\.com/ || "$1" =~ ^https://raw\.githubusercontent\.com/ || "$1" =~ ^https://objects\.githubusercontent\.com/ || "$1" =~ ^https://github-releases\.githubusercontent\.com/ ]]; }
gh_url(){
  local url="$1"
  if [[ -n "${GH_PROXY:-}" ]] && is_github_url "$url"; then
    printf '%s/%s\n' "${GH_PROXY%/}" "$url"
  else
    printf '%s\n' "$url"
  fi
}

curl_gh(){
  local out="$1" url="$2"
  curl -fL --retry 3 -A "clash-for-linux-install/1.0" -o "$out" "$(gh_url "$url")"
}

repo_raw_url(){
  printf 'https://raw.githubusercontent.com/%s/%s/%s\n' "$PROJECT_REPO" "$PROJECT_BRANCH" "$1"
}

install_deps(){
  local missing=()
  for c in curl grep sed awk tar gzip unzip chmod chown mkdir systemctl ss; do has "$c" || missing+=("$c"); done
  if ((${#missing[@]}==0)); then return 0; fi
  warn "缺少依赖：${missing[*]}，尝试自动安装"
  if has apt-get; then apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y curl grep sed gawk tar gzip unzip coreutils iproute2 ca-certificates
  elif has dnf; then dnf install -y curl grep sed gawk tar gzip unzip coreutils iproute ca-certificates
  elif has yum; then yum install -y curl grep sed gawk tar gzip unzip coreutils iproute ca-certificates
  elif has apk; then apk add --no-cache curl grep sed gawk tar gzip unzip coreutils iproute2 ca-certificates
  elif has pacman; then pacman -Sy --noconfirm curl grep sed gawk tar gzip unzip coreutils iproute2 ca-certificates
  else err "无法识别包管理器，请先安装：${missing[*]}"; exit 1; fi
}

detect_arch(){
  local m; m="$(uname -m)"
  case "$m" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l|armv7) echo "armv7" ;;
    armv6l|armv6) echo "armv6" ;;
    i386|i686) echo "386" ;;
    *) err "暂不支持架构：$m"; exit 1 ;;
  esac
}

port_in_use(){ ss -lntup 2>/dev/null | awk '{print $5}' | grep -Eq "[:.]$1$"; }
find_free_port(){
  local p start="${1:-7890}"
  for ((p=start; p<start+200; p++)); do
    if ! port_in_use "$p"; then echo "$p"; return 0; fi
  done
  err "无法在 ${start}-$((start+199)) 找到空闲端口"; exit 1
}

get_latest_asset(){
  local repo="$1" pattern="$2" exclude="${3:-$^}"
  curl -fsSL "$(gh_url "https://api.github.com/repos/${repo}/releases/latest")" \
    | grep -oE '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]+"' \
    | sed -E 's/^.*"(https:[^"]+)".*$/\1/' \
    | grep -Ei "$pattern" \
    | grep -Eiv "$exclude" \
    | head -n1
}

download_mihomo(){
  local arch="$1" tmp="$2" url="" candidates=()
  info "检测到系统架构：$arch"

  if [[ -n "${MIHOMO_URL:-}" ]]; then
    info "使用指定 Mihomo 下载地址：$MIHOMO_URL"
    curl_gh "$tmp/mihomo.gz" "$MIHOMO_URL"
  else
    if [[ "$arch" == "amd64" ]]; then
      candidates+=("archives/mihomo-linux-amd64-compatible.gz")
      candidates+=("archives/mihomo-linux-amd64.gz")
    else
      candidates+=("archives/mihomo-linux-${arch}.gz")
    fi

    for f in "${candidates[@]}"; do
      url="$(repo_raw_url "$f")"
      info "尝试从本仓库离线包下载 Mihomo：$f"
      if curl_gh "$tmp/mihomo.gz" "$url"; then
        break
      fi
      rm -f "$tmp/mihomo.gz"
    done

    if [[ ! -s "$tmp/mihomo.gz" ]]; then
      warn "本仓库 archives/ 未找到 ${arch} 内核包，尝试 GitHub Release。"
      if [[ "$arch" == "amd64" ]]; then
        url="$(get_latest_asset "$MIHOMO_REPO" "mihomo-linux-${arch}.*compatible.*\.gz$" "\.deb|\.rpm" || true)"
      fi
      [[ -n "$url" ]] || url="$(get_latest_asset "$MIHOMO_REPO" "mihomo-linux-${arch}.*\.gz$" "\.deb|\.rpm" || true)"
      if [[ -n "$url" ]]; then
        info "下载 Mihomo：$url"
        curl_gh "$tmp/mihomo.gz" "$url"
      fi
    fi
  fi

  if [[ ! -s "$tmp/mihomo.gz" ]]; then
    warn "没有自动找到适合 ${arch} 的 Mihomo 内核。"
    echo "你可以："
    echo "1) 把内核包上传到仓库 archives/，例如 amd64 放 archives/mihomo-linux-amd64-compatible.gz"
    echo "2) 现在粘贴 Mihomo .gz 直链继续安装"
    read -r -p "请输入 Mihomo .gz 下载地址（留空退出）：" manual_url
    [[ -n "$manual_url" ]] || { err "未提供 Mihomo 内核下载地址，安装退出。"; exit 1; }
    curl_gh "$tmp/mihomo.gz" "$manual_url"
  fi

  [[ -s "$tmp/mihomo.gz" ]] || { err "Mihomo 内核下载失败。"; exit 1; }
  gzip -dc "$tmp/mihomo.gz" > "$INSTALL_DIR/bin/mihomo"
  chmod +x "$INSTALL_DIR/bin/mihomo"
}

download_zashboard(){
  local tmp="$1" url=""
  url="$(repo_raw_url "archives/dist.zip")"
  info "尝试从本仓库离线包下载 Zashboard：archives/dist.zip"
  if ! curl_gh "$tmp/zashboard.zip" "$url"; then
    rm -f "$tmp/zashboard.zip"
    url="$(get_latest_asset "$ZASHBOARD_REPO" "(dist|zashboard).*\.zip$" || true)"
    if [[ -z "$url" ]]; then
      warn "未找到 Zashboard release zip，尝试下载 gh-pages 分支"
      url="https://github.com/${ZASHBOARD_REPO}/archive/refs/heads/gh-pages.zip"
    fi
    info "下载 Zashboard：$url"
    curl_gh "$tmp/zashboard.zip" "$url"
  fi
  rm -rf "$INSTALL_DIR/ui"
  mkdir -p "$INSTALL_DIR/ui"
  unzip -q "$tmp/zashboard.zip" -d "$tmp/zashboard"
  local index_dir
  index_dir="$(find "$tmp/zashboard" -type f -name index.html -printf '%h\n' | head -n1 || true)"
  [[ -n "$index_dir" ]] || { err "Zashboard 包中未找到 index.html"; exit 1; }
  cp -a "$index_dir"/. "$INSTALL_DIR/ui/"
}

ask_subscription(){
  local sub="${SUB_URL:-}"
  while [[ -z "$sub" ]]; do
    read -r -p "请输入订阅链接 URL（必填）：" sub
  done
  printf '%s\n' "$sub"
}

write_base_files(){
  local sub_url="$1" mixed="$2" http="$3" socks="$4" ctrl="$5" secret="$6"
  mkdir -p "$CONFIG_DIR" "$INSTALL_DIR/bin" "$INSTALL_DIR/ui" /var/log
  cat > "$CONFIG_DIR/env" <<EOF
SUB_URL='$sub_url'
GH_PROXY='$GH_PROXY'
MIXED_PORT='$mixed'
HTTP_PORT='$http'
SOCKS_PORT='$socks'
CONTROLLER_PORT='$ctrl'
SECRET='$secret'
TUN_ENABLE='false'
EOF
  chmod 600 "$CONFIG_DIR/env"

  cat > "$CONFIG_DIR/mixin.yaml" <<EOF
# Mixin 配置：可用 clash 菜单修改端口、密钥、TUN 等
mixed-port: $mixed
port: $http
socks-port: $socks
allow-lan: true
bind-address: '*'
mode: rule
log-level: info
external-controller: 0.0.0.0:$ctrl
secret: "$secret"
external-ui: $INSTALL_DIR/ui
external-ui-name: zashboard
unified-delay: true
tcp-concurrent: true
profile:
  store-selected: true
  store-fake-ip: true
tun:
  enable: false
  stack: mixed
  auto-route: true
  auto-detect-interface: true
  dns-hijack:
    - any:53
dns:
  enable: true
  listen: 0.0.0.0:1053
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  default-nameserver:
    - 223.5.5.5
    - 119.29.29.29
  nameserver:
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query
EOF

  cat > "$CONFIG_DIR/config.yaml" <<EOF
# 自动生成的说明文件。
# 实际运行文件：$CONFIG_DIR/runtime.yaml
# 订阅文件：$CONFIG_DIR/subscription.yaml
# Mixin 覆盖：$CONFIG_DIR/mixin.yaml
EOF
}

merge_config(){
  local sub_file="$CONFIG_DIR/subscription.yaml" mixin_file="$CONFIG_DIR/mixin.yaml" runtime_file="$CONFIG_DIR/runtime.yaml" clean_file
  [[ -s "$sub_file" ]] || { err "订阅配置不存在：$sub_file"; return 1; }
  clean_file="$(mktemp)"
  # 清理订阅里常见的本机运行时字段，避免 YAML 顶层重复键导致 Mihomo 解析失败。
  awk '
    function is_runtime_key(line){
      return line ~ /^(mixed-port|port|socks-port|redir-port|tproxy-port|allow-lan|bind-address|mode|log-level|external-controller|external-ui|external-ui-name|secret|unified-delay|tcp-concurrent|profile|tun|dns):/
    }
    /^[^[:space:]#][^:]*:/ {
      skip = is_runtime_key($0)
    }
    skip { next }
    { print }
  ' "$sub_file" > "$clean_file"
  awk 'FNR==1 && NR!=1 { print "" } { print }' "$clean_file" "$mixin_file" > "$runtime_file"
  rm -f "$clean_file"
}

import_subscription(){
  # shellcheck disable=SC1091
  source "$CONFIG_DIR/env"
  info "导入订阅配置"
  curl -fL --retry 3 -A "clash-for-linux-install/1.0" -o "$CONFIG_DIR/subscription.yaml" "$SUB_URL"
  merge_config
  success "订阅已导入：$CONFIG_DIR/subscription.yaml"
}

install_service(){
  cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=Mihomo Proxy Core
Documentation=https://github.com/MetaCubeX/mihomo
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$RUN_USER
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=false
ExecStart=$INSTALL_DIR/bin/mihomo -d $CONFIG_DIR -f $CONFIG_DIR/runtime.yaml
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576
StandardOutput=append:/var/log/mihomo.log
StandardError=append:/var/log/mihomo.log

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now "$SERVICE_NAME"
}

install_cli(){
  cat > "$BIN_DIR/clash" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
CONFIG_DIR="/etc/mihomo"
INSTALL_DIR="/opt/mihomo"
SERVICE_NAME="mihomo"
ENV_FILE="$CONFIG_DIR/env"
MIHOMO_REPO="${MIHOMO_REPO:-MetaCubeX/mihomo}"
GH_PROXY="${GH_PROXY:-}"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info(){ echo -e "${BLUE}[INFO]${NC} $*"; }; ok(){ echo -e "${GREEN}[OK]${NC} $*"; }; warn(){ echo -e "${YELLOW}[WARN]${NC} $*"; }; err(){ echo -e "${RED}[ERR]${NC} $*" >&2; }
root(){ [[ ${EUID:-$(id -u)} -eq 0 ]] || { err "此操作需要 root：sudo clash"; exit 1; }; }
load(){ [[ -f "$ENV_FILE" ]] && source "$ENV_FILE"; }
save_env(){ cat > "$ENV_FILE" <<EOV
SUB_URL='${SUB_URL:-}'
GH_PROXY='${GH_PROXY:-}'
MIXED_PORT='${MIXED_PORT:-7890}'
HTTP_PORT='${HTTP_PORT:-7891}'
SOCKS_PORT='${SOCKS_PORT:-7892}'
CONTROLLER_PORT='${CONTROLLER_PORT:-9090}'
SECRET='${SECRET:-}'
TUN_ENABLE='${TUN_ENABLE:-false}'
EOV
chmod 600 "$ENV_FILE"; }
port_in_use(){ ss -lntup 2>/dev/null | awk '{print $5}' | grep -Eq "[:.]$1$"; }
find_free_port(){ local p start="${1:-7890}"; for ((p=start;p<start+200;p++)); do port_in_use "$p" || { echo "$p"; return; }; done; err "没有空闲端口"; exit 1; }
rand_secret(){ tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32 || date +%s%N | sha256sum | cut -c1-32; }
is_github_url(){ [[ "$1" =~ ^https://(api\.)?github\.com/ || "$1" =~ ^https://raw\.githubusercontent\.com/ || "$1" =~ ^https://objects\.githubusercontent\.com/ || "$1" =~ ^https://github-releases\.githubusercontent\.com/ ]]; }
gh_url(){ local url="$1"; if [[ -n "${GH_PROXY:-}" ]] && is_github_url "$url"; then printf '%s/%s\n' "${GH_PROXY%/}" "$url"; else printf '%s\n' "$url"; fi; }
curl_gh(){ local out="$1" url="$2"; curl -fL --retry 3 -A "clash-for-linux-install/1.0" -o "$out" "$(gh_url "$url")"; }
merge_config(){ local clean; clean="$(mktemp)"; awk 'function k(line){return line ~ /^(mixed-port|port|socks-port|redir-port|tproxy-port|allow-lan|bind-address|mode|log-level|external-controller|external-ui|external-ui-name|secret|unified-delay|tcp-concurrent|profile|tun|dns):/} /^[^[:space:]#][^:]*:/ {skip=k($0)} skip {next} {print}' "$CONFIG_DIR/subscription.yaml" > "$clean"; awk 'FNR==1 && NR!=1 {print ""} {print}' "$clean" "$CONFIG_DIR/mixin.yaml" > "$CONFIG_DIR/runtime.yaml"; rm -f "$clean"; }
restart(){ systemctl restart "$SERVICE_NAME" && ok "服务已重启" || { err "重启失败，查看日志：journalctl -u $SERVICE_NAME -e"; exit 1; }; }
show_access(){ load; local ip; ip="$(hostname -I 2>/dev/null | awk '{print $1}')"; [[ -n "$ip" ]] || ip="127.0.0.1"; echo; ok "Zashboard: http://${ip}:${CONTROLLER_PORT}/ui/"; ok "控制器: http://${ip}:${CONTROLLER_PORT}"; ok "密钥: ${SECRET}"; echo; }
set_yaml_key(){ local key="$1" val="$2" file="$CONFIG_DIR/mixin.yaml"; if grep -qE "^${key}:" "$file"; then sed -i -E "s#^${key}:.*#${key}: ${val}#" "$file"; else printf '\n%s: %s\n' "$key" "$val" >> "$file"; fi; }
set_tun(){ local val="$1"; sed -i -E "0,/^[[:space:]]*enable:/s#^([[:space:]]*)enable:.*#\1enable: ${val}#" "$CONFIG_DIR/mixin.yaml"; }
import_sub(){ root; load; read -r -p "订阅链接（留空使用当前）：" new_sub; [[ -n "$new_sub" ]] && SUB_URL="$new_sub"; [[ -n "${SUB_URL:-}" ]] || { err "订阅链接不能为空"; exit 1; }; save_env; curl -fL --retry 3 -A "clash-for-linux-install/1.0" -o "$CONFIG_DIR/subscription.yaml" "$SUB_URL"; merge_config; restart; ok "订阅已重新导入"; }
proxy_on(){ root; systemctl start "$SERVICE_NAME"; ok "代理已开启"; show_access; }
proxy_off(){ root; systemctl stop "$SERVICE_NAME"; ok "代理已关闭"; }
secret_menu(){ root; load; echo "当前密钥：${SECRET}"; read -r -p "是否重新生成密钥？[y/N] " y; [[ "$y" =~ ^[Yy]$ ]] || return; SECRET="$(rand_secret)"; save_env; sed -i -E "s#^secret:.*#secret: \"${SECRET}\"#" "$CONFIG_DIR/mixin.yaml"; merge_config; restart; show_access; }
tun_menu(){ root; load; echo "当前 TUN：${TUN_ENABLE:-false}"; read -r -p "开启 TUN？[y/N] " y; if [[ "$y" =~ ^[Yy]$ ]]; then TUN_ENABLE=true; set_tun true; else TUN_ENABLE=false; set_tun false; fi; save_env; merge_config; restart; ok "TUN 已设置为：$TUN_ENABLE"; }
mixin_menu(){ root; load; echo "当前端口：mixed=$MIXED_PORT http=$HTTP_PORT socks=$SOCKS_PORT controller=$CONTROLLER_PORT"; read -r -p "Mixed 端口（留空不改/auto 自动）：" v; [[ "$v" == "auto" ]] && v="$(find_free_port 7890)"; [[ -n "$v" ]] && MIXED_PORT="$v" && set_yaml_key mixed-port "$v"; read -r -p "HTTP 端口（留空不改/auto 自动）：" v; [[ "$v" == "auto" ]] && v="$(find_free_port 7891)"; [[ -n "$v" ]] && HTTP_PORT="$v" && set_yaml_key port "$v"; read -r -p "SOCKS 端口（留空不改/auto 自动）：" v; [[ "$v" == "auto" ]] && v="$(find_free_port 7892)"; [[ -n "$v" ]] && SOCKS_PORT="$v" && set_yaml_key socks-port "$v"; read -r -p "Controller 端口（留空不改/auto 自动）：" v; [[ "$v" == "auto" ]] && v="$(find_free_port 9090)"; [[ -n "$v" ]] && CONTROLLER_PORT="$v" && set_yaml_key external-controller "0.0.0.0:$v"; save_env; merge_config; restart; show_access; }
detect_arch(){ case "$(uname -m)" in x86_64|amd64) echo amd64;; aarch64|arm64) echo arm64;; armv7l|armv7) echo armv7;; armv6l|armv6) echo armv6;; i386|i686) echo 386;; *) err "不支持架构：$(uname -m)"; exit 1;; esac; }
asset(){ curl -fsSL "$(gh_url "https://api.github.com/repos/$1/releases/latest")" | grep -oE '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]+"' | sed -E 's/^.*"(https:[^"]+)".*$/\1/' | grep -Ei "$2" | grep -Eiv "${3:-$^}" | head -n1; }
upgrade_core(){ root; local arch url tmp; arch="$(detect_arch)"; read -r -p "指定 Mihomo 下载 URL（留空自动下载最新版）：" url; if [[ -z "$url" ]]; then [[ "$arch" == amd64 ]] && url="$(asset "$MIHOMO_REPO" "mihomo-linux-${arch}.*compatible.*\.gz$" "\.deb|\.rpm" || true)"; [[ -n "$url" ]] || url="$(asset "$MIHOMO_REPO" "mihomo-linux-${arch}.*\.gz$" "\.deb|\.rpm" || true)"; fi; [[ -n "$url" ]] || { err "未找到内核下载地址"; exit 1; }; tmp="$(mktemp -d)"; curl_gh "$tmp/mihomo.gz" "$url"; gzip -dc "$tmp/mihomo.gz" > "$INSTALL_DIR/bin/mihomo.new"; chmod +x "$INSTALL_DIR/bin/mihomo.new"; mv "$INSTALL_DIR/bin/mihomo.new" "$INSTALL_DIR/bin/mihomo"; rm -rf "$tmp"; restart; "$INSTALL_DIR/bin/mihomo" -v || true; }
diagnose(){ load; echo "== 服务状态 =="; systemctl --no-pager status "$SERVICE_NAME" || true; echo; echo "== 端口监听 =="; ss -lntup | grep -E "(${MIXED_PORT:-7890}|${HTTP_PORT:-7891}|${SOCKS_PORT:-7892}|${CONTROLLER_PORT:-9090})" || true; echo; echo "== 版本 =="; "$INSTALL_DIR/bin/mihomo" -v || true; echo; echo "== Zashboard =="; show_access; echo "== 最近日志 =="; journalctl -u "$SERVICE_NAME" -n 80 --no-pager || tail -n 80 /var/log/mihomo.log || true; }
logs(){ journalctl -u "$SERVICE_NAME" -f --no-pager || tail -f /var/log/mihomo.log; }
uninstall(){ root; read -r -p "确认卸载并清理所有安装内容？[y/N] " y; [[ "$y" =~ ^[Yy]$ ]] || exit 0; systemctl disable --now "$SERVICE_NAME" 2>/dev/null || true; rm -f "/etc/systemd/system/${SERVICE_NAME}.service"; systemctl daemon-reload || true; rm -rf "$INSTALL_DIR" "$CONFIG_DIR" /var/log/mihomo.log /usr/local/bin/clash; ok "已卸载并清理安装内容"; }
menu(){ while true; do echo; echo "========== Mihomo + Zashboard 菜单 =========="; echo "1) 开启代理"; echo "2) 关闭代理"; echo "3) 重新导入订阅"; echo "4) 设置/查看密钥"; echo "5) 开启/关闭 TUN 模式"; echo "6) Mixin 配置管理（端口等）"; echo "7) 升级当前或指定内核"; echo "8) 诊断功能"; echo "9) 显示日志"; echo "10) 重启程序"; echo "11) 卸载程序"; echo "12) 显示 Zashboard 地址和密钥"; echo "0) 退出"; read -r -p "请选择：" n; case "$n" in 1) proxy_on;; 2) proxy_off;; 3) import_sub;; 4) secret_menu;; 5) tun_menu;; 6) mixin_menu;; 7) upgrade_core;; 8) diagnose;; 9) logs;; 10) root; restart;; 11) uninstall; exit 0;; 12) show_access;; 0) exit 0;; *) warn "无效选择";; esac; done; }
case "${1:-menu}" in on) proxy_on;; off) proxy_off;; sub) import_sub;; secret) secret_menu;; tun) tun_menu;; mixin) mixin_menu;; upgrade) upgrade_core;; doctor|diagnose) diagnose;; log|logs) logs;; restart) root; restart;; uninstall) uninstall;; ui|status) show_access;; menu|*) menu;; esac
EOF
  chmod +x "$BIN_DIR/clash"
}

main(){
  need_root
  choose_github_proxy
  install_deps
  mkdir -p "$INSTALL_DIR/bin" "$INSTALL_DIR/ui" "$CONFIG_DIR"
  local tmp arch sub mixed http socks ctrl secret
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  arch="$(detect_arch)"
  mixed="$(find_free_port 7890)"
  http="$(find_free_port 7891)"
  socks="$(find_free_port 7892)"
  ctrl="$(find_free_port 9090)"
  secret="$(rand_secret)"
  sub="$(ask_subscription)"
  write_base_files "$sub" "$mixed" "$http" "$socks" "$ctrl" "$secret"
  download_mihomo "$arch" "$tmp"
  download_zashboard "$tmp"
  import_subscription
  install_service
  install_cli
  success "安装完成，已设置开机自启"
  echo
  echo "Mihomo 端口：mixed=$mixed http=$http socks=$socks controller=$ctrl"
  local ip; ip="$(hostname -I 2>/dev/null | awk '{print $1}')"; [[ -n "$ip" ]] || ip="127.0.0.1"
  echo "Zashboard 访问地址：http://${ip}:${ctrl}/ui/"
  echo "密钥：${secret}"
  echo
  echo "SSH 中输入 clash 可打开管理菜单。"
}

main "$@"
