#!/bin/sh

NZ_BASE_PATH="/opt/nezha"
NZ_AGENT_PATH="${NZ_BASE_PATH}/agent"
NZ_AGENT_BIN="${NZ_AGENT_PATH}/nezha-agent"

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

set_config_value() {
    config=$1
    key=$2
    value=${3:-true}

    if grep -q "^[[:space:]]*${key}[[:space:]]*:" "$config"; then
        sudo sed -i "s|^[[:space:]]*${key}[[:space:]]*:.*|${key}: ${value}|" "$config"
    fi
}

usage() {
    printf '%s\n' \
        "用法：disable_agent_unsafe_features.sh [--allow-command-execute]" \
        "" \
        "  （无参数）                 禁用命令执行/在线终端/文件列表、内网穿透、自动更新" \
        "  --allow-command-execute   不禁止命令执行（disable_command_execute 写为 false），" \
        "                            内网穿透与自动更新仍保持禁用"
}

disable_agent_unsafe_features() {
    echo "开始禁用 nezha-agent 不安全特性..."

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
        if [ "$allow_command_execute" -eq 1 ]; then
            echo "  - disable_command_execute：允许命令执行、在线终端、文件列表"
            command_execute_value=false
        else
            echo "  - disable_command_execute：禁用命令执行、在线终端、文件列表"
            command_execute_value=true
        fi
        echo "  - disable_nat：禁用内网穿透"
        echo "  - disable_auto_update：禁用自动更新"

        if ! set_config_value "$config" "disable_command_execute" "$command_execute_value"; then
            err "更新 disable_command_execute 失败：$config"
            overall_status=1
            continue
        fi

        if ! set_config_value "$config" "disable_nat"; then
            err "更新 disable_nat 失败：$config"
            overall_status=1
            continue
        fi

        # 保持 disable_force_update 不变，以保留远程更新 agent 的能力。
        if ! set_config_value "$config" "disable_auto_update"; then
            err "更新 disable_auto_update 失败：$config"
            overall_status=1
            continue
        fi

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

allow_command_execute=0
for arg in "$@"; do
    case "$arg" in
        --allow-command-execute) allow_command_execute=1 ;;
        -h|--help) usage; exit 0 ;;
        *) err "未知参数：$arg"; exit 1 ;;
    esac
done

disable_agent_unsafe_features
