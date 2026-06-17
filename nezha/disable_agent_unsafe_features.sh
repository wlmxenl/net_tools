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

    if grep -q "^[[:space:]]*${key}[[:space:]]*:" "$config"; then
        sudo sed -i "s|^[[:space:]]*${key}[[:space:]]*:.*|${key}: true|" "$config"
    fi
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
        echo "  - disable_command_execute：禁用命令执行、在线终端、文件列表"
        echo "  - disable_nat：禁用内网穿透"
        echo "  - disable_auto_update：禁用自动更新"

        if ! set_config_value "$config" "disable_command_execute"; then
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

disable_agent_unsafe_features
