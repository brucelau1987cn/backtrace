#!/usr/bin/env bash
# =============================================================
#  backtrace.sh v3 —— 回程路由质量检测脚本
#  支持: Debian/Ubuntu/CentOS/RHEL/Alpine/Arch/macOS
#
#  关键修复（v3）：
#  nexttrace --raw 输出格式为竖线分隔：
#    ttl|ip|ptr|rtt|asn|省|市|区|街|owner|lat|lon
#  ASN 字段是纯数字（第5列），无 "AS" 前缀！
#  必须用 awk/cut 按列提取，或用 --classic 模式匹配 [AS4134]
# =============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; MAGENTA='\033[0;35m'
BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

NAMES=(
  "北京电信" "北京联通" "北京移动"
  "上海电信" "上海联通" "上海移动"
  "广州电信" "广州联通" "广州移动"
)
HOSTS=(
  "ipv4.pek-4134.endpoint.nxtrace.org"
  "ipv4.pek-4837.endpoint.nxtrace.org"
  "ipv4.pek-9808.endpoint.nxtrace.org"
  "ipv4.sha-4134.endpoint.nxtrace.org"
  "ipv4.sha-4837.endpoint.nxtrace.org"
  "ipv4.sha-9808.endpoint.nxtrace.org"
  "ipv4.can-4134.endpoint.nxtrace.org"
  "ipv4.can-4837.endpoint.nxtrace.org"
  "ipv4.can-9808.endpoint.nxtrace.org"
)

NEXTTRACE_BIN=""
TIMEOUT=35
MAX_HOPS=30

# ───────────────────────────────────────────────────────────────

detect_os() {
  if   [[ "$OSTYPE" == "darwin"* ]];  then echo "macos"
  elif [[ -f /etc/alpine-release ]];  then echo "alpine"
  elif [[ -f /etc/arch-release ]];    then echo "arch"
  elif [[ -f /etc/debian_version ]];  then echo "debian"
  elif [[ -f /etc/redhat-release ]] || [[ -f /etc/centos-release ]]; then echo "rhel"
  else echo "unknown"; fi
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64)  echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7*)        echo "armv7" ;;
    *)             echo "amd64" ;;
  esac
}

log_ok()   { echo -e "${GREEN}[OK]${RESET}    $*"; }
log_info() { echo -e "${CYAN}[INFO]${RESET}  $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${RESET}  $*"; }

# ═══════════════════════════════════════════════════════════════
# DNS 解析
# ═══════════════════════════════════════════════════════════════

resolve_ip() {
  local host="$1" ip=""
  command -v getent   &>/dev/null && ip=$(getent ahostsv4 "$host" 2>/dev/null | awk 'NR==1{print $1}')
  [[ -z "$ip" ]] && command -v dig      &>/dev/null && ip=$(dig +short +time=5 A "$host" 2>/dev/null | grep -E '^[0-9]+\.' | head -1)
  [[ -z "$ip" ]] && command -v host     &>/dev/null && ip=$(host -t A "$host" 2>/dev/null | awk '/has address/{print $NF}' | head -1)
  [[ -z "$ip" ]] && command -v nslookup &>/dev/null && ip=$(nslookup "$host" 2>/dev/null | awk '/^Address/ && !/#/{print $2}' | head -1)
  [[ -z "$ip" ]] && command -v python3  &>/dev/null && ip=$(python3 -c "import socket; print(socket.gethostbyname('$host'))" 2>/dev/null)
  echo "${ip:-}"
}

# ═══════════════════════════════════════════════════════════════
# 安装 nexttrace
# ═══════════════════════════════════════════════════════════════

install_nexttrace() {
  local os arch tmp_dir dst
  os=$(detect_os); arch=$(detect_arch)
  tmp_dir=$(mktemp -d)

  log_info "尝试官方安装脚本..."
  if command -v curl &>/dev/null; then
    bash <(curl -sL https://github.com/nxtrace/NTrace-core/raw/main/nt_install.sh) &>/dev/null 2>&1 || true
    if command -v nexttrace &>/dev/null; then
      NEXTTRACE_BIN="nexttrace"; log_ok "nexttrace 安装成功"; rm -rf "$tmp_dir"; return 0
    fi
  fi

  local base="https://github.com/nxtrace/NTrace-core/releases/latest/download"
  local bin_name
  case "$os-$arch" in
    linux-amd64)  bin_name="nexttrace_linux_amd64"    ;;
    linux-arm64)  bin_name="nexttrace_linux_arm64"    ;;
    linux-armv7)  bin_name="nexttrace_linux_arm32v7"  ;;
    macos-amd64)  bin_name="nexttrace_darwin_amd64"   ;;
    macos-arm64)  bin_name="nexttrace_darwin_arm64"   ;;
    alpine-*)     bin_name="nexttrace_linux_${arch}_musl" ;;
    *)            bin_name="nexttrace_linux_amd64"    ;;
  esac

  log_info "下载 $bin_name ..."
  if curl -sL --connect-timeout 15 "${base}/${bin_name}" -o "${tmp_dir}/nexttrace" 2>/dev/null \
     && chmod +x "${tmp_dir}/nexttrace" \
     && "${tmp_dir}/nexttrace" --version &>/dev/null 2>&1; then
    if [[ -w /usr/local/bin ]]; then dst="/usr/local/bin/nexttrace"
    else mkdir -p "${HOME}/.local/bin"; dst="${HOME}/.local/bin/nexttrace"; export PATH="${HOME}/.local/bin:$PATH"; fi
    mv "${tmp_dir}/nexttrace" "$dst"
    NEXTTRACE_BIN="$dst"; log_ok "安装成功: $dst"
    rm -rf "$tmp_dir"; return 0
  fi
  rm -rf "$tmp_dir"; log_warn "安装失败，尝试备用工具"; return 1
}

ensure_nexttrace() {
  if command -v nexttrace &>/dev/null; then
    NEXTTRACE_BIN="nexttrace"
    log_ok "检测到 nexttrace: $(nexttrace --version 2>&1 | head -1)"; return 0
  fi
  for p in /usr/local/bin/nexttrace "${HOME}/.local/bin/nexttrace"; do
    [[ -x "$p" ]] && { NEXTTRACE_BIN="$p"; log_ok "找到 nexttrace: $p"; return 0; }
  done
  printf "${YELLOW}未找到 nexttrace，是否安装？[Y/n]${RESET} "
  local ans; read -r ans </dev/tty 2>/dev/null || ans="Y"
  case "${ans:-Y}" in [Yy]*) install_nexttrace ;; *) log_warn "跳过"; return 1 ;; esac
}

# ═══════════════════════════════════════════════════════════════
# 本机信息
# ═══════════════════════════════════════════════════════════════

get_local_info() {
  local json ip country city org
  json=$(curl -s --connect-timeout 6 "https://ipinfo.io/json" 2>/dev/null || true)
  [[ -z "$json" ]] && { echo "无法获取本机出口信息"; return; }
  ip=$(     printf '%s' "$json" | grep -o '"ip"[^,]*'      | grep -o '"[^"]*"$' | tr -d '"')
  country=$(printf '%s' "$json" | grep -o '"country"[^,]*' | grep -o '"[^"]*"$' | tr -d '"')
  city=$(   printf '%s' "$json" | grep -o '"city"[^,]*'    | grep -o '"[^"]*"$' | tr -d '"')
  org=$(    printf '%s' "$json" | grep -o '"org"[^,]*'     | grep -o '"[^"]*"$' | tr -d '"')
  echo "IP: ${ip}  国家: ${country}  城市: ${city}  服务商: ${org}"
}

# ═══════════════════════════════════════════════════════════════
# 执行 trace，获取原始输出
# ═══════════════════════════════════════════════════════════════

run_trace() {
  local target="$1" raw=""

  if [[ -n "$NEXTTRACE_BIN" ]]; then
    # ── 策略1：--raw 模式（管道输出，竖线分隔，ASN在第5列为纯数字）
    # 格式: ttl|ip|ptr|rtt|asn|...|owner|lat|lon
    raw=$(timeout "$TIMEOUT" "$NEXTTRACE_BIN" \
        --raw -n -q 1 --max-hops "$MAX_HOPS" \
        "$target" 2>/dev/null || true)

    if [[ -n "$raw" ]]; then
      echo "$raw"; return
    fi

    # ── 策略2：--classic 模式（彩色但管道时退化，含 [AS4134] 格式）
    raw=$(timeout "$TIMEOUT" "$NEXTTRACE_BIN" \
        --classic -n -q 1 --max-hops "$MAX_HOPS" \
        "$target" 2>/dev/null || true)

    if [[ -n "$raw" ]]; then
      echo "$raw"; return
    fi

    # ── 策略3：默认模式（去掉颜色码后解析）
    raw=$(timeout "$TIMEOUT" "$NEXTTRACE_BIN" \
        -n -q 1 --max-hops "$MAX_HOPS" --no-color \
        "$target" 2>/dev/null || true)

    [[ -n "$raw" ]] && { echo "$raw"; return; }
  fi

  # ── 备用：mtr
  if command -v mtr &>/dev/null; then
    raw=$(timeout "$TIMEOUT" mtr --report --raw --no-dns --report-cycles 1 "$target" 2>/dev/null || true)
    [[ -n "$raw" ]] && { echo "$raw"; return; }
  fi

  # ── 备用：traceroute -A（部分版本支持显示AS号）
  if command -v traceroute &>/dev/null; then
    raw=$(timeout "$TIMEOUT" traceroute -n -A -m "$MAX_HOPS" "$target" 2>/dev/null \
       || timeout "$TIMEOUT" traceroute -n    -m "$MAX_HOPS" "$target" 2>/dev/null \
       || true)
    [[ -n "$raw" ]] && { echo "$raw"; return; }
  fi

  echo ""
}

# ═══════════════════════════════════════════════════════════════
# 从原始输出提取所有 ASN（返回以空格分隔的纯数字列表）
#
# 支持多种格式：
#   --raw:     ttl|ip|ptr|rtt|4809|...   → 提取第5列数字
#   --classic: ... [AS4809] ...          → 提取方括号内数字
#   --table:   | 4809 |                  → 提取表格数字列
#   mtr:       p 4 1.2.3.4              → 提取后续数字（mtr --raw 无ASN，跳过）
#   traceroute -A: [AS4809] 1.2.3.4     → 提取方括号内数字
# ═══════════════════════════════════════════════════════════════

extract_asns() {
  local raw="$1"
  local asns=""

  # 方法1：--raw 管道格式（竖线分隔，第5列是纯数字ASN）
  # 行格式: 数字|ip|ptr|rtt|ASN数字|...
  # 过滤掉 ASN=0 (私网/未知)
  local pipe_asns
  pipe_asns=$(echo "$raw" | awk -F'|' '
    NF >= 5 && $1 ~ /^[0-9]+$/ && $5 ~ /^[0-9]+$/ && $5 != "0" {
      print $5
    }
  ')
  asns="$asns $pipe_asns"

  # 方法2：[AS4809] 格式（--classic / traceroute -A）
  local bracket_asns
  bracket_asns=$(echo "$raw" | grep -oE '\[AS[0-9]+\]' | grep -oE '[0-9]+')
  asns="$asns $bracket_asns"

  # 方法3：AS4809 格式（无括号，部分输出）
  local plain_asns
  plain_asns=$(echo "$raw" | grep -oE '\bAS[0-9]+\b' | grep -oE '[0-9]+')
  asns="$asns $plain_asns"

  # 去重、过滤空行
  echo "$asns" | tr ' ' '\n' | grep -E '^[0-9]+$' | grep -v '^0$' | sort -u | tr '\n' ' '
}

# ═══════════════════════════════════════════════════════════════
# 分析线路类型
# ═══════════════════════════════════════════════════════════════

analyze_route() {
  local raw="$1"
  local asns
  asns=$(extract_asns "$raw")

  # 调试用
  if [[ "${BACKTRACE_DEBUG:-0}" == "1" ]]; then
    echo "[DEBUG] ASNs found: $asns" >&2
  fi

  # 辅助函数：判断某 ASN 是否存在
  has_asn() { echo " $asns " | grep -qw "$1"; }

  local has_4134=0 has_4809=0 has_4812=0
  local has_9929=0 has_10099=0 has_4837=0
  local has_58807=0 has_9808=0 has_cn2_bb=0

  has_asn 4134  && has_4134=1
  has_asn 4809  && has_4809=1
  has_asn 4812  && has_4812=1
  has_asn 9929  && has_9929=1
  has_asn 10099 && has_10099=1
  has_asn 4837  && has_4837=1
  has_asn 58807 && has_58807=1
  has_asn 9808  && has_9808=1

  # CN2 骨干：59.43.x.x（无需依赖 ASN 标注）
  echo "$raw" | grep -qE '\b59\.43\.[0-9]{1,3}\.[0-9]{1,3}\b' && has_cn2_bb=1

  # 优先级判断
  if   [[ $has_4809 -eq 1 && $has_4134 -eq 1 ]]; then echo "CN2GT"
  elif [[ $has_4809 -eq 1 ]];                     then echo "CN2GIA"
  elif [[ $has_cn2_bb -eq 1 ]];                   then echo "CN2"
  elif [[ $has_9929 -eq 1 && $has_10099 -eq 1 ]]; then echo "联通9929精品"
  elif [[ $has_9929 -eq 1 ]];                     then echo "联通9929"
  elif [[ $has_58807 -eq 1 ]];                    then echo "移动CMIN2"
  elif [[ $has_10099 -eq 1 && $has_4837 -eq 1 ]]; then echo "联通4837"
  elif [[ $has_4837 -eq 1 ]];                     then echo "联通4837"
  elif [[ $has_9808 -eq 1 ]];                     then echo "移动CMI"
  elif [[ $has_4134 -eq 1 && $has_4812 -eq 1 ]];  then echo "电信163"
  elif [[ $has_4134 -eq 1 ]];                     then echo "电信163"
  else echo "未知线路"; fi
}

grade_line() {
  case "$1" in
    CN2GIA)      echo "★★★ [高端精品]" ;;
    CN2GT)       echo "★★☆ [优质线路]" ;;
    CN2)         echo "★★☆ [CN2骨干]"  ;;
    联通9929精品) echo "★★☆ [优质线路]" ;;
    联通9929)    echo "★☆☆ [普通线路]" ;;
    移动CMIN2)   echo "★★☆ [优质线路]" ;;
    电信163)     echo "★☆☆ [普通线路]" ;;
    联通4837)    echo "★☆☆ [普通线路]" ;;
    移动CMI)     echo "★☆☆ [普通线路]" ;;
    *)           echo "☆☆☆ [未知]"      ;;
  esac
}

color_line() {
  case "$1" in
    CN2GIA|CN2GT|CN2)              echo "$MAGENTA" ;;
    联通9929精品|移动CMIN2)        echo "$CYAN"    ;;
    电信163|联通4837|移动CMI|联通9929) echo "$GREEN" ;;
    *)                             echo "$DIM"     ;;
  esac
}

# ═══════════════════════════════════════════════════════════════
# 主流程
# ═══════════════════════════════════════════════════════════════

main() {
  echo -e "${BOLD}${BLUE}"
  cat << 'EOF'
  ╔══════════════════════════════════════════════════════╗
  ║      backtrace.sh v3 —— 回程路由质量检测            ║
  ║  CN2GIA / CN2GT / 163 / 联通 / 移动 线路识别       ║
  ╚══════════════════════════════════════════════════════╝
EOF
  echo -e "${RESET}"

  echo -e "${BOLD}${BLUE}▶ 环境准备${RESET}"
  ensure_nexttrace || true
  echo ""

  echo -e "${BOLD}${BLUE}▶ 本机出口信息${RESET}"
  echo -e "  $(get_local_info)"
  echo ""

  echo -e "${BOLD}${BLUE}▶ 回程路由检测（共 ${#NAMES[@]} 个节点）${RESET}"
  printf "${BOLD}%-12s %-18s %-14s %s${RESET}\n" "节点" "目标IP" "线路类型" "等级"
  printf '%s\n' "$(printf '─%.0s' {1..68})"

  declare -A TYPE_COUNT=()

  for i in "${!NAMES[@]}"; do
    local name="${NAMES[$i]}"
    local host="${HOSTS[$i]}"

    printf "${DIM}  %-10s 解析中...${RESET}                          \r" "$name"
    local dest_ip
    dest_ip=$(resolve_ip "$host")

    if [[ -z "$dest_ip" ]]; then
      printf "%-12s %-18s ${YELLOW}%-14s${RESET} %s\n" "$name" "N/A" "DNS失败" "无法解析目标地址"
      TYPE_COUNT["DNS失败"]=$(( ${TYPE_COUNT["DNS失败"]:-0} + 1 ))
      continue
    fi

    printf "${DIM}  %-10s %-18s 探测路由...${RESET}                  \r" "$name" "$dest_ip"
    local raw
    raw=$(run_trace "$dest_ip")

    if [[ "${BACKTRACE_DEBUG:-0}" == "1" ]]; then
      echo "" >&2
      echo -e "${YELLOW}=== DEBUG: $name ($dest_ip) ===${RESET}" >&2
      echo "$raw" | head -40 >&2
      echo "==============================" >&2
    fi

    # 检查是否有任何路由信息
    local hop_count
    hop_count=$(echo "$raw" | grep -cE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' 2>/dev/null || echo 0)

    if [[ -z "$raw" || "$hop_count" -eq 0 ]]; then
      printf "%-12s %-18s ${YELLOW}%-14s${RESET} %s\n" \
        "$name" "$dest_ip" "路由超时" "检测不到回程路由节点的IPV4地址"
      TYPE_COUNT["路由超时"]=$(( ${TYPE_COUNT["路由超时"]:-0} + 1 ))
      continue
    fi

    local line_type grade color
    line_type=$(analyze_route "$raw")
    grade=$(grade_line "$line_type")
    color=$(color_line "$line_type")

    printf "%-12s %-18s ${color}%-14s${RESET} %s\n" \
      "$name" "$dest_ip" "$line_type" "$grade"
    TYPE_COUNT["$line_type"]=$(( ${TYPE_COUNT["$line_type"]:-0} + 1 ))
  done

  echo ""
  printf '%s\n' "$(printf '═%.0s' {1..68})"
  echo -e "${BOLD}检测完成！线路类型统计：${RESET}"
  for t in "${!TYPE_COUNT[@]}"; do
    local c
    c=$(color_line "$t")
    printf "  ${c}%-16s${RESET} %d 个节点\n" "$t" "${TYPE_COUNT[$t]}"
  done
  echo ""
  echo -e "${DIM}调试模式：BACKTRACE_DEBUG=1 bash $0${RESET}"
  echo ""
}

main "$@"
