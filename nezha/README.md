# Nezha 探针脚本合集

哪吒监控（nezha-agent）常用运维脚本，默认安装路径为 `/opt/nezha/agent`。

仓库地址：<https://github.com/wlmxenl/net_tools>

## 使用前提

- Linux 服务器，已安装 `systemd`。
- 使用 `root` 用户执行，或已安装 `sudo` 的普通用户（脚本内部会自动加 `sudo`）。
- 已通过官方脚本安装 nezha-agent，配置文件位于 `/opt/nezha/agent/config*.yml`。

## 脚本列表

| 脚本 | 作用 |
| --- | --- |
| `disable_agent_unsafe_features.sh` | 关闭命令执行/在线终端/文件列表、内网穿透、自动更新 |
| `uninstall_agent.sh` | 停服并彻底卸载 nezha-agent |

## 一键运行

默认禁用全部不安全特性：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/wlmxenl/net_tools/main/nezha/disable_agent_unsafe_features.sh)
```

保留命令执行（内网穿透与自动更新仍禁用）：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/wlmxenl/net_tools/main/nezha/disable_agent_unsafe_features.sh) --allow-command-execute
```

卸载 nezha-agent：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/wlmxenl/net_tools/main/nezha/uninstall_agent.sh)
```

说明：`bash <(curl ...)` 需要 bash（主流 Linux 默认自带），脚本参数写在右括号之后。

## disable_agent_unsafe_features.sh

### 参数

| 参数 | 说明 |
| --- | --- |
| （无参数） | `disable_command_execute`、`disable_nat`、`disable_auto_update` 全部写为 `true` |
| `--allow-command-execute` | 仅 `disable_command_execute` 写为 `false`，放开命令执行/在线终端/文件列表；另外两项仍写为 `true` |
| `-h`、`--help` | 显示帮助 |

### 配置项影响

| 配置项 | 无参数 | `--allow-command-execute` |
| --- | --- | --- |
| `disable_command_execute` | `true` | `false` |
| `disable_nat` | `true` | `true` |
| `disable_auto_update` | `true` | `true` |
| `disable_force_update` | 不修改 | 不修改 |

`disable_force_update` 始终不修改，以保留远程更新 agent 的能力。

### 行为说明

- 遍历 `/opt/nezha/agent` 下所有 `config*.yml`，逐个修改后重启对应服务。
- 配置文件里不存在某个键时会跳过该键，不会主动新增；agent 对这些键的缺省值等同于未禁用。
- 修改失败或重启失败会输出红色错误提示，最终以退出码 `1` 结束。

### 手动放开内网穿透/自动更新

脚本只提供命令执行的单独开关。需要放开另外两项时，修改配置后重启服务：

```bash
sudo sed -i 's/^disable_nat: true/disable_nat: false/; s/^disable_auto_update: true/disable_auto_update: false/' /opt/nezha/agent/config.yml
sudo /opt/nezha/agent/nezha-agent service -c /opt/nezha/agent/config.yml restart
```

存在多个 `config*.yml` 时逐一处理。

## 安全提示

`--allow-command-execute` 会重新开启面板的命令执行能力：任何持有面板管理员权限的人都能在该服务器上执行任意命令，仅在明确需要时使用。

## 卸载说明

`uninstall_agent.sh` 会停止并移除所有相关服务，然后删除 `/opt/nezha/agent` 目录（不可恢复）；若 `/opt/nezha` 已为空，则一并删除该父目录。需要重新安装时，卸载后再按官方脚本安装即可。
