# 🛰️ Backtrace

> VPS 回程线路检测脚本：一键查看到中国大陆三网的回程路由、线路类型和关键入口节点。

<p align="center">
  <img alt="Shell" src="https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white">
  <img alt="Platform" src="https://img.shields.io/badge/Platform-Linux-blue?style=flat-square&logo=linux&logoColor=white">
  <img alt="Trace" src="https://img.shields.io/badge/Trace-NextTrace%20%7C%20besttrace%20%7C%20mtr%20%7C%20traceroute-orange?style=flat-square">
</p>

## ✨ 项目简介

Backtrace 是一个面向 VPS / 独立服务器的回程线路检测工具。
它会自动检测到北京、上海、广州三地三网的回程路由，并根据关键 ASN / IP 段识别线路类型，例如：

- 电信：CN2 GIA / CN2 GT / 163
- 联通：9929 / CUG / 4837
- 移动：CMIN2 / CMI / CMNET

适合用来快速判断机器回国线路质量、入口节点和基础延迟。

## 🚀 一键运行

普通运行：

```bash
curl -fsSL https://raw.githubusercontent.com/brucelau1987cn/backtrace/main/backtrace.sh | bash
```

推荐使用 root 权限运行，便于自动安装缺失依赖：

```bash
curl -fsSL https://raw.githubusercontent.com/brucelau1987cn/backtrace/main/backtrace.sh | sudo bash
```

> 非交互环境下运行时，脚本会自动进入快速检测模式。

## 🧭 检测目标

| 城市 | 电信 | 联通 | 移动 |
| --- | --- | --- | --- |
| 北京 | ✅ | ✅ | ✅ |
| 上海 | ✅ | ✅ | ✅ |
| 广州 | ✅ | ✅ | ✅ |

## 🔍 检测模式

启动后可选择三种模式：

| 模式 | 说明 |
| --- | --- |
| 快速检测 | 显示线路类型、延迟和关键判断节点 |
| 详细检测 | 显示完整路由追踪，并对关键线路 / 运营商打标 |
| 指定目标 | 选择单个节点进行检测 |

## 🧩 工具优先级

脚本会自动选择可用的路由追踪工具：

1. `traceroute`：无需 API，快速检测优先使用
2. `tracepath`：无需安装概率高、无 API 限制、无需 root，作为兜底
3. `mtr`
4. `nexttrace`：仅作为已安装时的备用方案
5. `besttrace`：仅作为已安装时的备用方案

默认优先使用系统已有工具，不再自动安装 NextTrace，避免 API 访问限制。快速检测会并发检测多个目标，减少等待时间。

## 🧠 识别能力

支持识别常见国内回程线路：

| 运营商 | 线路类型 |
| --- | --- |
| 电信 | CN2 GIA、CN2 GT、CTG、163 |
| 联通 | 9929、CUG、CUG+4837、4837 |
| 移动 | CMIN2、CMI、CMNET |

线路识别规则集中维护在脚本顶部的规则库中：

- `LINE_ASN_MAP`：ASN → 线路标签
- `LINE_IP_RULES`：IP 段正则 → 线路标签

规则库已补充常见高置信 ASN / IP 段，例如：

- 电信：`AS4809` / `59.43`、`AS4134` / `202.97`、`AS23764` / `69.194` / `203.22.17x`
- 联通：`AS9929` / `218.105` / `210.51`、`AS10099` / `202.77.23`、`AS4837` / `219.158` / `221.4-7`
- 移动：`AS58807` / 高段 `223.120`、`AS58453` / `223.120` / `223.118-121`、`AS9808` / `221.176-183` / `120.192-199`

需要新增线路类型、ASN 或 IP 段时，优先更新这两处规则。

同时会展示用于识别线路的关键节点，例如：

```text
202.77.23.29[CUG]
```

便于快速判断实际线路类型。

## 🖥️ 系统支持

已针对常见 Linux 环境做兼容：

- Ubuntu / Debian
- RHEL / CentOS / Rocky / AlmaLinux
- Fedora
- Arch Linux

> macOS 可手动安装依赖后尝试运行，但自动依赖安装主要面向 Linux。

## 📌 示例输出

```text
╭──────────────────────────── 回程路由检测 ────────────────────────────╮
│ 工具: traceroute   并发: 9  超时: 12s                                │
├──────────┬────────────┬──────────────────┬────────────────────┤
│ 目标     │ 等级       │ 线路             │ 判断节点           │
├──────────┼────────────┼──────────────────┼────────────────────┤
  北京电信   ◆ 优质      CN2 GT             35.7ms   59.43.x.x[CN2]
  上海联通   ★ 顶级      联通9929           37.3ms   218.105.x.x[9929]
  广州移动   ★ 顶级      移动CMIN2          19.3ms   223.120.x.x[CMIN2]
╰──────────┴────────────┴──────────────────┴────────────────────╯
```

## 📄 许可证

本项目基于 **GNU Affero General Public License v3.0 (AGPL-3.0-only)** 开源。

详见 [LICENSE](LICENSE)。

## ⚠️ 说明

- 路由结果受运营商调度、目标节点、当前网络状态影响，可能随时间变化。
- 自动识别基于常见 ASN / IP 段规则，适合快速判断，不等同于官方线路证明。
- 建议多次测试、不同时间段交叉观察。
