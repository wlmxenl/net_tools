# NaiveProxy 一键安装脚本

基于官方 [klzgrad/forwardproxy](https://github.com/klzgrad/forwardproxy) 发布的 Caddy forwardproxy naive 版本，自动安装 Caddy、生成服务端配置，并输出 v2rayN 导入链接。

## 使用前提

- 使用 `root` 用户执行。
- 仅支持 `x86_64/amd64` 架构。
- 准备一个已解析到当前服务器公网 IP 的域名。
- 确保服务器 `443/tcp` 端口未被其他程序占用，且安全组/防火墙已放行。

## 一键运行

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/wlmxenl/net_tools/main/install_naiveproxy/naive.sh)
```
