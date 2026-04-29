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
| 快速检测 | 显示线路类型、延迟和关键入口节点 |
| 详细检测 | 显示完整路由追踪，并对关键线路 / 运营商打标 |
| 指定目标 | 选择单个节点进行检测 |

## 🧩 工具优先级

脚本会自动选择可用的路由追踪工具：

1. `nexttrace`
2. `besttrace`
3. `mtr`
4. `traceroute`

优先使用 NextTrace；如果不可用，会尝试安装或自动降级到其他工具。

## 🧠 识别能力

支持识别常见国内回程线路：

| 运营商 | 线路类型 |
| --- | --- |
| 电信 | CN2 GIA、CN2 GT、163 |
| 联通 | 9929、CUG、4837 |
| 移动 | CMIN2、CMI、CMNET |

同时会展示：

```text
国内口上一跳[运营商] -> 国内入口第一跳[线路]
```

便于快速判断实际入口质量。

## 🖥️ 系统支持

已针对常见 Linux 环境做兼容：

- Ubuntu / Debian
- RHEL / CentOS / Rocky / AlmaLinux
- Fedora
- Arch Linux

> macOS 可手动安装依赖后尝试运行，但自动依赖安装主要面向 Linux。

## 📌 示例输出

```text
北京电信  CN2 GT    [优质线路]  延迟: 35.7ms  入口: 69.194.x.x[CTGNet] -> 59.43.x.x[CN2]
上海电信  CN2 GIA   [顶级线路]  延迟: 28.0ms  入口: 69.194.x.x[CTGNet] -> 59.43.x.x[CN2]
广州移动  移动CMIN2 [顶级线路]  延迟: 19.2ms  入口: 9.x.x.x -> 223.120.x.x[CMIN2]
```

## ⚠️ 说明

- 路由结果受运营商调度、目标节点、当前网络状态影响，可能随时间变化。
- 自动识别基于常见 ASN / IP 段规则，适合快速判断，不等同于官方线路证明。
- 建议多次测试、不同时间段交叉观察。
