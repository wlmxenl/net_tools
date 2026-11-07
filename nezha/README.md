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
| `edit_agent_config.sh` | 按参数启用/禁用命令执行、内网穿透、自动更新 |
| `uninstall_agent.sh` | 停服并彻底卸载 nezha-agent |

## 一键运行

全部禁用（命令执行、内网穿透、自动更新）：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/wlmxenl/net_tools/main/nezha/edit_agent_config.sh) --disable-command-execute --disable-nat --disable-auto-update
```

仅放开内网穿透（其余项不动）：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/wlmxenl/net_tools/main/nezha/edit_agent_config.sh) --enable-nat
```

卸载 nezha-agent：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/wlmxenl/net_tools/main/nezha/uninstall_agent.sh)
```

说明：`bash <(curl ...)` 需要 bash（主流 Linux 默认自带），脚本参数写在右括号之后。

## edit_agent_config.sh

### 参数

| 参数 | 说明 |
| --- | --- |
| （无参数） | 仅显示用法，不修改任何配置 |
| `--disable-command-execute` | `disable_command_execute` 写为 `true`，禁用命令执行/在线终端/文件列表 |
| `--enable-command-execute` | `disable_command_execute` 写为 `false`，放开命令执行/在线终端/文件列表 |
| `--disable-nat` | `disable_nat` 写为 `true`，禁用内网穿透 |
| `--enable-nat` | `disable_nat` 写为 `false`，放开内网穿透 |
| `--disable-auto-update` | `disable_auto_update` 写为 `true`，禁用自动更新 |
| `--enable-auto-update` | `disable_auto_update` 写为 `false`，放开自动更新 |
| `-h`、`--help` | 显示帮助 |

规则：

- 至少指定一个开关，否则只显示用法并以退出码 `1` 结束。
- 只修改显式指定的配置项，未指定的项保持原值不动。
- 同一项同时传 `--disable-X` 与 `--enable-X` 会报错退出。

### 配置项影响示例

以 `--enable-nat` 为例（其余项不动）：

| 配置项 | 结果 |
| --- | --- |
| `disable_nat` | `false` |
| `disable_command_execute` | 保持原值 |
| `disable_auto_update` | 保持原值 |
| `disable_force_update` | 不修改 |

`disable_force_update` 始终不修改，以保留远程更新 agent 的能力。

### 行为说明

- 遍历 `/opt/nezha/agent` 下所有 `config*.yml`，逐个修改后重启对应服务。
- 配置文件里不存在某个键时会跳过该键，不会主动新增；agent 对这些键的缺省值等同于未禁用。
- 修改失败或重启失败会输出红色错误提示，最终以退出码 `1` 结束。

## 安全提示

`--enable-command-execute` 会重新开启面板的命令执行能力：任何持有面板管理员权限的人都能在该服务器上执行任意命令，仅在明确需要时使用。

## 卸载说明

`uninstall_agent.sh` 会停止并移除所有相关服务，然后删除 `/opt/nezha/agent` 目录（不可恢复）；若 `/opt/nezha` 已为空，则一并删除该父目录。需要重新安装时，卸载后再按官方脚本安装即可。
