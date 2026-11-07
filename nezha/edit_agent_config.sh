#!/bin/sh

NZ_BASE_PATH="/opt/nezha"
NZ_AGENT_PATH="${NZ_AGENT_PATH:-${NZ_BASE_PATH}/agent}"
NZ_AGENT_BIN="${NZ_AGENT_BIN:-${NZ_AGENT_PATH}/nezha-agent}"

red='\033[0;31m'
green='\033[0;32m'
plain='\033[0m'

err() {
    printf "${red}%s${plain}\n" "$*" >&2
}

success() {
    printf "${green}%s${plain}\n" "$*"
}

sudo() {
    myEUID=$(id -ru)
    if [ "$myEUID" -ne 0 ]; then
        if command -v sudo > /dev/null 2>&1; then
            command sudo "$@"
        else
            err "错误：系统未安装 sudo，无法继续执行。"
            exit 1
        fi
    else
        "$@"
    fi
}

# set_config_value <config> <key> <value>
# 键已存在时改写为指定值；不存在时跳过（不新增），返回 1 并保持静默，由调用方提示。
set_config_value() {
    config=$1
    key=$2
    value=$3

    if grep -q "^[[:space:]]*${key}[[:space:]]*:" "$config"; then
        sudo sed -i "s|^[[:space:]]*${key}[[:space:]]*:.*|${key}: ${value}|" "$config"
        return 0
    fi
    return 1
}

usage() {
    printf '%s\n' \
        "用法：edit_agent_config.sh <选项>..." \
        "" \
        "至少指定一个开关；未指定的配置项保持原值不动。" \
        "" \
        "  --disable-command-execute    disable_command_execute: true（禁用命令执行/在线终端/文件列表）" \
        "  --enable-command-execute     disable_command_execute: false（放开命令执行/在线终端/文件列表）" \
        "  --disable-nat                disable_nat: true（禁用内网穿透）" \
        "  --enable-nat                 disable_nat: false（放开内网穿透）" \
        "  --disable-auto-update        disable_auto_update: true（禁用自动更新）" \
        "  --enable-auto-update         disable_auto_update: false（放开自动更新）" \
        "  -h, --help                   显示本帮助" \
        "" \
        "示例：" \
        "  edit_agent_config.sh --disable-command-execute --disable-nat --disable-auto-update" \
        "  edit_agent_config.sh --enable-nat"
}

# update_one <config> <key> <value> <desc>
update_one() {
    config=$1
    key=$2
    value=$3
    desc=$4

    if [ "$value" = "true" ]; then
        echo "  - ${key}：${desc}（写为 true）"
    else
        echo "  - ${key}：${desc}（写为 false）"
    fi

    if ! set_config_value "$config" "$key" "$value"; then
        echo "  - ${key}：配置中不存在，跳过"
    fi
}

edit_agent_config() {
    if [ ! -d "$NZ_AGENT_PATH" ]; then
        err "未找到 nezha-agent 安装目录：$NZ_AGENT_PATH"
        exit 1
    fi

    if [ ! -x "$NZ_AGENT_BIN" ]; then
        err "未找到 nezha-agent 可执行文件：$NZ_AGENT_BIN"
        exit 1
    fi

    config_files=$(find "$NZ_AGENT_PATH" -name "config*.yml" 2>/dev/null)

    if [ -z "$config_files" ]; then
        err "在 $NZ_AGENT_PATH 中未找到配置文件"
        exit 1
    fi

    overall_status=0
    echo "已找到配置文件，开始更新配置..."

    for config in $config_files; do
        echo "正在更新配置：$config"

        if [ "$command_execute_set" -eq 1 ]; then
            update_one "$config" "disable_command_execute" "$command_execute_value" "命令执行/在线终端/文件列表"
        fi
        if [ "$nat_set" -eq 1 ]; then
            update_one "$config" "disable_nat" "$nat_value" "内网穿透"
        fi
        if [ "$auto_update_set" -eq 1 ]; then
            update_one "$config" "disable_auto_update" "$auto_update_value" "自动更新"
        fi
        # 保持 disable_force_update 不变，以保留远程更新 agent 的能力。

        echo "正在重启对应服务：$config"
        if ! sudo "$NZ_AGENT_BIN" service -c "$config" restart >/dev/null 2>&1; then
            err "重启服务失败：$config"
            overall_status=1
            continue
        fi

        success "已更新并重启：$config"
    done

    if [ "$overall_status" -ne 0 ]; then
        err "部分 nezha-agent 配置更新失败"
        exit 1
    fi
}

command_execute_set=0
command_execute_value=
nat_set=0
nat_value=
auto_update_set=0
auto_update_value=

conflict() {
    err "参数冲突：$1 不能同时指定 --disable 与 --enable。"
    exit 1
}

if [ $# -eq 0 ]; then
    usage >&2
    err "错误：至少需要指定一个开关。"
    exit 1
fi

for arg in "$@"; do
    case "$arg" in
        --disable-command-execute)
            [ "$command_execute_set" -eq 1 ] && [ "$command_execute_value" = "false" ] && conflict "$arg"
            command_execute_set=1
            command_execute_value=true
            ;;
        --enable-command-execute)
            [ "$command_execute_set" -eq 1 ] && [ "$command_execute_value" = "true" ] && conflict "$arg"
            command_execute_set=1
            command_execute_value=false
            ;;
        --disable-nat)
            [ "$nat_set" -eq 1 ] && [ "$nat_value" = "false" ] && conflict "$arg"
            nat_set=1
            nat_value=true
            ;;
        --enable-nat)
            [ "$nat_set" -eq 1 ] && [ "$nat_value" = "true" ] && conflict "$arg"
            nat_set=1
            nat_value=false
            ;;
        --disable-auto-update)
            [ "$auto_update_set" -eq 1 ] && [ "$auto_update_value" = "false" ] && conflict "$arg"
            auto_update_set=1
            auto_update_value=true
            ;;
        --enable-auto-update)
            [ "$auto_update_set" -eq 1 ] && [ "$auto_update_value" = "true" ] && conflict "$arg"
            auto_update_set=1
            auto_update_value=false
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            err "未知参数：$arg"
            usage >&2
            exit 1
            ;;
    esac
done

edit_agent_config
