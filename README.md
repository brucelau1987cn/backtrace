# 🛰️ Backtrace

> 一键检测 VPS 到中国大陆三网的回程线路。

<p align="center">
  <img alt="Shell" src="https://img.shields.io/badge/Shell-Bash-4EAA25?style=flat-square&logo=gnubash&logoColor=white">
  <img alt="Platform" src="https://img.shields.io/badge/Platform-Linux-blue?style=flat-square&logo=linux&logoColor=white">
  <img alt="License" src="https://img.shields.io/badge/License-AGPL--3.0-blue?style=flat-square">
</p>

Backtrace 用来快速判断 VPS 回国线路质量。
默认检测北京、上海、广州三地三网，输出线路类型、延迟和关键判断节点。

支持识别：

- 电信：CN2 GIA / CN2 GT / CTG / 163Plus / 163
- 联通：9929 / CUG / CUG+4837 / 4837
- 移动：CMIN2 / CMI / CMNET

## 🚀 使用

```bash
curl -fsSL https://raw.githubusercontent.com/brucelau1987cn/backtrace/main/backtrace.sh | bash
```

脚本默认执行快速检测，不需要选择模式。

## 📌 输出示例

```text
回程路由检测 (traceroute, 并发 9, 超时 12s)
────────────────────────────────────────────────────────
北京
    北京电信  ◆ 优质  CN2 GT      35.6ms  59.43.x.x[CN2]
    北京联通  ★ 顶级  联通9929    41.2ms  218.105.x.x[9929]
    北京移动  ★ 顶级  移动CMIN2   47.6ms  223.120.x.x[CMIN2]

上海
    上海电信  ★ 顶级  CN2 GIA     28.0ms  59.43.x.x[CN2]
    上海联通  ★ 顶级  联通9929    37.3ms  218.105.x.x[9929]
    上海移动  ★ 顶级  移动CMIN2   35.5ms  223.120.x.x[CMIN2]
```

图例：

- `★ 顶级`：精品线路
- `◆ 优质`：优化线路
- `△ 普通`：普通骨干
- 判断节点：用于识别线路的关键 IP / ASN 节点

## 🧩 工具选择

脚本优先使用系统已有工具，不依赖 NextTrace API。

优先级：

1. `traceroute`
2. `tracepath`
3. `mtr`
4. 已安装的 `nexttrace`
5. 已安装的 `besttrace`

如果系统没有可用追踪工具，建议安装：

```bash
apt install -y traceroute
```

## 🧠 识别规则

线路规则集中维护在脚本顶部：

- `LINE_ASN_MAP`：ASN → 线路标签
- `LINE_IP_RULES`：IP 段 → 线路标签

纯 `202.97 / AS4134` 默认判断为 `电信163 [普通线路]`。
只有延迟达到 163Plus 阈值时，才判断为 `电信163Plus [优质线路]`：

- 广州 `<25ms`
- 上海 `<45ms`
- 北京 `<55ms`

## 📄 License

GNU Affero General Public License v3.0.
See [LICENSE](LICENSE).

## ⚠️ 说明

路由会受运营商调度、目标节点和当前网络状态影响。
本脚本适合快速判断线路类型，不等同于官方线路证明。
