#!/usr/bin/env bash

set -Eeuo pipefail

trap 'echo "Script failed at line ${LINENO}." >&2' ERR

SCRIPT_NAME="$(basename "$0")"
INSTALL_DIR="/etc/caddy"
WWW_DIR="/var/www/html"
HTML_INDEX="${WWW_DIR}/index.html"
HTML_SOURCE_URL="https://raw.githubusercontent.com/wlmxenl/net_tools/refs/heads/main/install_naiveproxy/index.html"
STATE_DIR="/var/lib/caddy"
BIN_PATH="/usr/bin/caddy"
SERVICE_NAME="caddy"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
ROOT_INFO_DIR="/root/naiveproxy"
CLIENT_INFO="${ROOT_INFO_DIR}/config.json"

log() {
  printf '[*] %s\n' "$*"
}

die() {
  printf '[!] %s\n' "$*" >&2
  exit 1
}

require_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Please run this script as root."
}

require_systemd() {
  command -v systemctl >/dev/null 2>&1 || die "systemd is required."
}

require_arch() {
  case "$(uname -m)" in
    x86_64|amd64) ;;
    *)
      die "This installer currently supports x86_64/amd64 only, matching the published forwardproxy release."
      ;;
  esac
}

valid_domain() {
  local domain="$1"
  local label
  local -a labels

  [[ "$domain" =~ ^([a-z0-9-]+\.)+[a-z0-9-]{2,}$ ]] || return 1

  IFS='.' read -r -a labels <<< "$domain"
  for label in "${labels[@]}"; do
    [[ "$label" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]] || return 1
  done
}

valid_email() {
  [[ "$1" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}

read_domain() {
  while true; do
    read -r -p "请输入已解析到当前机器公网 IP 的域名：" DOMAIN
    DOMAIN="${DOMAIN,,}"
    if valid_domain "$DOMAIN"; then
      return
    fi

    printf '[!] 域名格式无效。正确示例：example.com\n' >&2
  done
}

read_contact_email() {
  while true; do
    read -r -p "Enter TLS contact email: " CONTACT_EMAIL
    if valid_email "$CONTACT_EMAIL"; then
      return
    fi

    printf '[!] Email is required and must be valid. Correct example: user@example.com\n' >&2
  done
}

random_string() {
  local length="$1"
  local bytes=$(( (length + 1) / 2 ))
  openssl rand -hex "$bytes" | cut -c1-"$length"
}

v2rayn_import_url() {
  local domain="$1"
  local username="$2"
  local password="$3"

  printf 'naive+https://%s:%s@%s:443#%s' "$username" "$password" "$domain" "$domain"
}

write_client_info() {
  local domain="$1"
  local username="$2"
  local password="$3"

  mkdir -p "$ROOT_INFO_DIR"
  chmod 700 "$ROOT_INFO_DIR"

  cat > "$CLIENT_INFO" <<EOF
{
  "listen": "socks://127.0.0.1:2080",
  "proxy": "https://${username}:${password}@${domain}"
}
EOF

  chmod 600 "$CLIENT_INFO"
}

read_client_proxy_url() {
  local proxy_url

  [[ -f "$CLIENT_INFO" ]] || return 1

  proxy_url="$(sed -n 's/.*"proxy"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CLIENT_INFO" | head -n1)"
  [[ -n "$proxy_url" ]] || return 1

  printf '%s\n' "$proxy_url"
}

client_configs_ready() {
  read_client_proxy_url >/dev/null 2>&1
}

rebuild_client_info_from_caddyfile() {
  local config="${INSTALL_DIR}/Caddyfile"
  local domain auth username password

  [[ -f "$config" ]] || return 1

  domain="$(sed -n 's/^[[:space:]]*:443,[[:space:]]*\([A-Za-z0-9.-]*\).*/\1/p' "$config" | head -n1)"
  [[ -n "$domain" ]] && valid_domain "$domain" || return 1

  auth="$(sed -n 's/^[[:space:]]*basic_auth[[:space:]]\+\([^[:space:]]\+\)[[:space:]]\+\([^[:space:]]\+\).*/\1 \2/p' "$config" | head -n1)"
  [[ "$auth" == *" "* ]] || return 1

  username="${auth%% *}"
  password="${auth#* }"
  [[ -n "$username" && -n "$password" ]] || return 1

  write_client_info "$domain" "$username" "$password"
}

ensure_client_info() {
  client_configs_ready && return 0
  rebuild_client_info_from_caddyfile
}

ensure_client_info_for_view() {
  client_configs_ready && return 0

  rebuild_client_info_from_caddyfile && return 0

  printf '[!] 客户端配置不存在，且无法从 Caddyfile 重新生成。\n' >&2
  return 1
}

client_proxy_url_from_client_info() {
  ensure_client_info || return 1
  read_client_proxy_url
}

v2rayn_import_url_from_client_info() {
  local proxy_url authority userinfo hostport domain username password

  proxy_url="$(client_proxy_url_from_client_info)" || return 1
  [[ "$proxy_url" == https://*@* ]] || return 1

  authority="${proxy_url#https://}"
  authority="${authority%%/*}"
  userinfo="${authority%@*}"
  hostport="${authority#*@}"
  [[ "$userinfo" == *:* && -n "$hostport" ]] || return 1

  username="${userinfo%%:*}"
  password="${userinfo#*:}"
  domain="${hostport%%:*}"
  [[ -n "$username" && -n "$password" && -n "$domain" ]] || return 1

  v2rayn_import_url "$domain" "$username" "$password"
}

install_packages() {
  log "Installing required packages..."

  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y curl ca-certificates tar xz-utils openssl
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache curl ca-certificates tar xz openssl
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y curl ca-certificates tar xz openssl
  elif command -v yum >/dev/null 2>&1; then
    yum install -y curl ca-certificates tar xz openssl
  else
    die "No supported package manager found (apt-get, apk, dnf, yum)."
  fi
}

prepare_assets() {
  local workdir="$1"
  local archive="${workdir}/caddy-forwardproxy-naive.tar.xz"
  local extract_dir="${workdir}/extract"
  local html_file="${workdir}/index.html"

  mkdir -p "$extract_dir"

  log "Downloading forwardproxy release..."
  curl -fL \
    -H "User-Agent: ${SCRIPT_NAME}" \
    "https://github.com/klzgrad/forwardproxy/releases/latest/download/caddy-forwardproxy-naive.tar.xz" \
    -o "$archive"

  log "Extracting binary..."
  tar -xJf "$archive" -C "$extract_dir"
  find "$extract_dir" -type f -name caddy -print -quit > "${workdir}/caddy-path.txt"
  [[ -s "${workdir}/caddy-path.txt" ]] || die "Could not find caddy binary in release archive."

  log "Downloading camouflage HTML..."
  curl -fL \
    -H "User-Agent: ${SCRIPT_NAME}" \
    "$HTML_SOURCE_URL" \
    -o "$html_file"
}

install_prepared_assets() {
  local workdir="$1"
  local caddy_src html_file www_parent
  caddy_src="$(<"${workdir}/caddy-path.txt")"
  html_file="${workdir}/index.html"
  www_parent="$(dirname "$WWW_DIR")"

  [[ -x "$caddy_src" ]] || die "Prepared Caddy binary not found or not executable."
  [[ -f "$html_file" ]] || die "Prepared HTML file not found."

  install -m 0755 "$caddy_src" "$BIN_PATH"

  mkdir -p "$WWW_DIR"
  install -m 0644 "$html_file" "$HTML_INDEX"
  chown root:root "$www_parent" "$WWW_DIR" "$HTML_INDEX"
  chmod 755 "$www_parent" "$WWW_DIR"
  chmod 644 "$HTML_INDEX"
}

ensure_caddy_user() {
  local nologin_shell
  nologin_shell="/usr/sbin/nologin"
  [[ -x "$nologin_shell" ]] || nologin_shell="/sbin/nologin"

  if ! getent group caddy >/dev/null 2>&1; then
    if command -v groupadd >/dev/null 2>&1; then
      groupadd --system caddy
    elif command -v addgroup >/dev/null 2>&1; then
      addgroup -S caddy
    else
      die "Could not create caddy group."
    fi
  fi

  if ! id -u caddy >/dev/null 2>&1; then
    if command -v useradd >/dev/null 2>&1; then
      useradd --system --gid caddy --create-home --home-dir "$STATE_DIR" --shell "$nologin_shell" caddy
    elif command -v adduser >/dev/null 2>&1; then
      adduser -S -D -h "$STATE_DIR" -s "$nologin_shell" -G caddy caddy
    else
      die "Could not create caddy user."
    fi
  fi
}

write_service_file() {
  log "Writing systemd service..."
  ensure_caddy_user
  mkdir -p "$INSTALL_DIR" "$STATE_DIR"
  chown root:caddy "$INSTALL_DIR"
  chown caddy:caddy "$STATE_DIR"
  chmod 750 "$INSTALL_DIR" "$STATE_DIR"

  cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Caddy
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
User=caddy
Group=caddy
ExecStart=${BIN_PATH} run --environ --config ${INSTALL_DIR}/Caddyfile
ExecReload=${BIN_PATH} reload --config ${INSTALL_DIR}/Caddyfile
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=512
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF
}

write_files() {
  local domain="$1"
  local username="$2"
  local password="$3"
  local contact_email="$4"

  log "Writing configuration..."
  ensure_caddy_user
  mkdir -p "$INSTALL_DIR" "$STATE_DIR"
  chown root:caddy "$INSTALL_DIR"
  chown caddy:caddy "$STATE_DIR"
  chmod 750 "$INSTALL_DIR" "$STATE_DIR"

  cat > "${INSTALL_DIR}/Caddyfile" <<EOF
{
  order forward_proxy before file_server
  log {
    exclude http.log.error
  }
}

:443, ${domain} {
  tls ${contact_email}
  encode
  forward_proxy {
    basic_auth ${username} ${password}
    hide_ip
    hide_via
    probe_resistance
  }
  file_server {
    root ${WWW_DIR}
  }
}
EOF

  chown root:caddy "${INSTALL_DIR}/Caddyfile"
  chmod 640 "${INSTALL_DIR}/Caddyfile"

  write_service_file

  write_client_info "$domain" "$username" "$password"
}

is_installed() {
  [[ -x "$BIN_PATH" && -f "$SERVICE_PATH" && -f "${INSTALL_DIR}/Caddyfile" ]]
}

format_and_validate_caddyfile() {
  local config="${INSTALL_DIR}/Caddyfile"

  if [[ ! -x "$BIN_PATH" ]]; then
    printf '[!] Caddy binary not found or not executable: %s\n' "$BIN_PATH" >&2
    return 1
  fi

  if [[ ! -f "$config" ]]; then
    printf '[!] Caddyfile not found: %s\n' "$config" >&2
    return 1
  fi

  log "Formatting Caddyfile..."
  if ! "$BIN_PATH" fmt --overwrite "$config"; then
    return 1
  fi

  if ! chown root:caddy "$config"; then
    return 1
  fi

  if ! chmod 640 "$config"; then
    return 1
  fi

  log "Validating Caddyfile..."
  if ! "$BIN_PATH" validate --config "$config"; then
    return 1
  fi
}

print_service_error() {
  printf '\n[!] Service error details:\n' >&2
  systemctl status "$SERVICE_NAME" --no-pager -l || true
  printf '\n[!] Recent logs:\n' >&2
  journalctl -u "$SERVICE_NAME" -n 50 --no-pager || true
}

restart_service() {
  if [[ ! -f "$SERVICE_PATH" ]]; then
    printf '[!] Service is not installed: %s\n' "$SERVICE_NAME" >&2
    return
  fi

  log "Restarting service..."
  systemctl daemon-reload
  if ! format_and_validate_caddyfile; then
    printf '[!] Caddyfile format or validation failed. Service restart skipped.\n' >&2
    return
  fi

  if systemctl restart "$SERVICE_NAME"; then
    log "Service restarted successfully."
  else
    printf '[!] Service restart failed.\n' >&2
    print_service_error
  fi
}

view_status() {
  if [[ ! -f "$SERVICE_PATH" ]]; then
    printf '[!] Service is not installed: %s\n' "$SERVICE_NAME" >&2
    return
  fi

  systemctl status "$SERVICE_NAME" --no-pager -l || true
}

print_v2rayn_import_url() {
  local import_url

  printf '\n===== v2rayN 一键导入 =====\n'
  if import_url="$(v2rayn_import_url_from_client_info)"; then
    printf '%s\n' "$import_url"
  else
    printf '[!] 无法从客户端配置生成 v2rayN 导入链接。\n' >&2
  fi
}

view_config() {
  cat <<EOF

===== 配置文件 =====
Caddyfile: ${INSTALL_DIR}/Caddyfile
网站目录: ${WWW_DIR}
运行数据目录: ${STATE_DIR}
Caddy 二进制: ${BIN_PATH}
systemd 服务: ${SERVICE_PATH}
客户端配置: ${CLIENT_INFO}
EOF

  ensure_client_info_for_view || true
  print_v2rayn_import_url
}

install_naiveproxy() {
  require_arch

  local domain username password contact_email tmpdir
  read_domain
  domain="$DOMAIN"
  read_contact_email
  contact_email="$CONTACT_EMAIL"

  install_packages

  username="u$(random_string 7)"
  password="$(random_string 24)"
  (
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT

    prepare_assets "$tmpdir"
    install_prepared_assets "$tmpdir"
    write_files "$domain" "$username" "$password" "$contact_email"

    if ! format_and_validate_caddyfile; then
      die "Caddyfile format or validation failed."
    fi

    log "Reloading systemd and starting service..."
    systemctl daemon-reload
    if systemctl enable --now "$SERVICE_NAME"; then
      log "Service started successfully."
    else
      printf '[!] Service start failed.\n' >&2
      print_service_error
      die "Installation stopped because service failed to start."
    fi
  )

  log "Verifying binary..."
  "$BIN_PATH" version >/dev/null

  cat <<EOF

Done.

Server:
  https://${domain}

Client config:
  ${CLIENT_INFO}

v2rayN import URL:
  $(v2rayn_import_url "$domain" "$username" "$password")

Credentials:
  username: ${username}
  password: ${password}

Quick check:
  systemctl status ${SERVICE_NAME}
  journalctl -u ${SERVICE_NAME} -f
EOF
}

upgrade_naiveproxy() {
  require_arch
  local tmpdir

  if ! is_installed; then
    install_naiveproxy
    return
  fi

  log "Existing installation detected. Upgrading Caddy binary and service..."
  install_packages
  (
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT

    prepare_assets "$tmpdir"
    install_prepared_assets "$tmpdir"
    write_service_file

    if ! format_and_validate_caddyfile; then
      printf '[!] Caddyfile format or validation failed. Service restart skipped.\n' >&2
      exit 0
    fi

    log "Reloading systemd and restarting service..."
    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME" >/dev/null

    if systemctl restart "$SERVICE_NAME"; then
      "$BIN_PATH" version >/dev/null
      log "Upgrade completed."
      view_config
    else
      printf '[!] Upgrade completed, but service restart failed.\n' >&2
      print_service_error
    fi
  )
}

uninstall_naiveproxy() {
  local confirm

  read -r -p "确认卸载？这会删除 Caddy 服务、配置文件、运行数据、客户端信息和 ${WWW_DIR}。输入 y 继续：" confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    log "已取消卸载。"
    return
  fi

  log "正在停止并禁用服务..."
  systemctl disable --now "$SERVICE_NAME" >/dev/null 2>&1 || true

  log "正在删除文件..."
  rm -f "$SERVICE_PATH" "$BIN_PATH"
  rm -rf "$INSTALL_DIR" "$STATE_DIR" "$ROOT_INFO_DIR" "$WWW_DIR"

  systemctl daemon-reload
  log "卸载完成。已删除脚本创建的文件和目录。"
}

show_menu() {
  cat <<EOF

NaiveProxy 管理脚本
1. 安装或升级
2. 重启服务
3. 查看运行状态
4. 查看配置
5. 卸载
0. 退出

EOF
}

pause_menu() {
  local unused
  printf '\n'
  read -r -p "按 Enter 返回菜单..." unused
}

main() {
  require_root
  require_systemd

  local choice

  while true; do
    show_menu
    read -r -p "请输入选项编号：" choice

    case "$choice" in
      1)
        upgrade_naiveproxy
        pause_menu
        ;;
      2)
        restart_service
        pause_menu
        ;;
      3)
        view_status
        pause_menu
        ;;
      4)
        view_config
        pause_menu
        ;;
      5)
        uninstall_naiveproxy
        pause_menu
        ;;
      0)
        log "已退出。"
        exit 0
        ;;
      *)
        printf '[!] 选项无效。正确示例：1\n' >&2
        pause_menu
        ;;
    esac
  done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main
fi
