#!/bin/bash
# ============================================================
# VPS 回程线路检测脚本 v2.5
# 检测到北京/上海/广州三网回程路由类型
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'

# ============================================================
# 目标节点
# ============================================================
declare -A TARGETS
TARGETS=(
    ["北京电信"]="ipv4.pek-4134.endpoint.nxtrace.org"
    ["北京联通"]="ipv4.pek-4837.endpoint.nxtrace.org"
    ["北京移动"]="ipv4.pek-9808.endpoint.nxtrace.org"
    ["上海电信"]="ipv4.sha-4134.endpoint.nxtrace.org"
    ["上海联通"]="ipv4.sha-4837.endpoint.nxtrace.org"
    ["上海移动"]="ipv4.sha-9808.endpoint.nxtrace.org"
    ["广州电信"]="ipv4.can-4134.endpoint.nxtrace.org"
    ["广州联通"]="ipv4.can-4837.endpoint.nxtrace.org"
    ["广州移动"]="ipv4.can-9808.endpoint.nxtrace.org"
)

ORDERED_KEYS=(
    "北京电信" "北京联通" "北京移动"
    "上海电信" "上海联通" "上海移动"
    "广州电信" "广州联通" "广州移动"
)

# ============================================================
# Banner
# ============================================================
print_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║              VPS 回程线路检测脚本 v2.5                  ║"
    echo "║          检测三网回程路由 & 线路类型识别                 ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "  检测时间: ${WHITE}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "  主机名称: ${WHITE}$(hostname)${NC}"
    echo -e "  系统信息: ${WHITE}$(uname -r)${NC}"

    echo -e "${YELLOW}[*] 获取本机 IP 信息...${NC}"
    local ipinfo
    ipinfo=$(curl -s --connect-timeout 5 https://ipinfo.io 2>/dev/null)

    if [ -n "$ipinfo" ] && echo "$ipinfo" | grep -q '"ip"'; then
        local ip org country city
        ip=$(echo "$ipinfo" | grep -oP '"ip"\s*:\s*"\K[^"]+')
        org=$(echo "$ipinfo" | grep -oP '"org"\s*:\s*"\K[^"]+')
        country=$(echo "$ipinfo" | grep -oP '"country"\s*:\s*"\K[^"]+')
        city=$(echo "$ipinfo" | grep -oP '"city"\s*:\s*"\K[^"]+')

        echo -e "  公网  IP: ${WHITE}${ip}${NC}"
        echo -e "  运营商  : ${WHITE}${org}${NC}"
        echo -e "  位置    : ${WHITE}${city}, ${country}${NC}"
    else
        local pub_ip
        pub_ip=$(curl -s --connect-timeout 5 ip.sb 2>/dev/null || echo "获取失败")
        echo -e "  公网  IP: ${WHITE}${pub_ip}${NC}"
        echo -e "  运营商  : ${WHITE}获取失败${NC}"
    fi
    echo ""
}

# ============================================================
# 安装依赖
# ============================================================
install_dependencies() {
    echo -e "${YELLOW}[*] 检查并安装必要工具...${NC}"

    if command -v apt-get &>/dev/null; then
        PKG_INSTALL="apt-get install -y"
    elif command -v yum &>/dev/null; then
        PKG_INSTALL="yum install -y"
    elif command -v dnf &>/dev/null; then
        PKG_INSTALL="dnf install -y"
    elif command -v pacman &>/dev/null; then
        PKG_INSTALL="pacman -S --noconfirm"
    fi

    if ! command -v traceroute &>/dev/null; then
        echo -e "${YELLOW}[*] 安装 traceroute...${NC}"
        $PKG_INSTALL traceroute >/dev/null 2>&1
    fi

    if ! command -v mtr &>/dev/null; then
        echo -e "${YELLOW}[*] 安装 mtr...${NC}"
        $PKG_INSTALL mtr >/dev/null 2>&1
    fi

    if ! command -v nexttrace &>/dev/null; then
        echo -e "${YELLOW}[*] 安装 nexttrace...${NC}"
        local arch
        arch=$(uname -m)
        case $arch in
            x86_64)  arch="amd64" ;;
            aarch64) arch="arm64" ;;
            armv7l)  arch="armv7" ;;
        esac
        local nt_url="https://github.com/nxtrace/NTrace-core/releases/latest/download/nexttrace_linux_${arch}"
        curl -sL "$nt_url" -o /usr/local/bin/nexttrace 2>/dev/null && \
        chmod +x /usr/local/bin/nexttrace && \
        echo -e "${GREEN}[✓] nexttrace 安装成功${NC}" || \
        echo -e "${RED}[✗] nexttrace 安装失败, 将使用 traceroute${NC}"
    fi

    if ! command -v dig &>/dev/null; then
        echo -e "${YELLOW}[*] 安装 dnsutils...${NC}"
        $PKG_INSTALL dnsutils >/dev/null 2>&1 || $PKG_INSTALL bind-utils >/dev/null 2>&1
    fi

    echo -e "${GREEN}[✓] 工具检查完成${NC}"
    echo ""
}

# ============================================================
# DNS 解析
# ============================================================
resolve_host() {
    local host="$1"
    local ip
    ip=$(dig +short "$host" 2>/dev/null | grep -oP '\d+\.\d+\.\d+\.\d+' | head -1)
    if [ -z "$ip" ]; then
        ip=$(getent hosts "$host" 2>/dev/null | awk '{print $1}' | head -1)
    fi
    [ -z "$ip" ] && ip="$host"
    echo "$ip"
}

# ============================================================
# 获取路由原始数据
# ============================================================
get_trace_data() {
    local ip="$1"
    if command -v nexttrace &>/dev/null; then
        nexttrace -q 1 -n "$ip" 2>/dev/null
    else
        traceroute -n -q 1 -m 30 -w 2 "$ip" 2>/dev/null
    fi
}

# ============================================================
# 识别单个 IP 的网络类型
# ============================================================
identify_ip_tag() {
    local ip="$1"

    # 排除私有地址
    if [[ "$ip" =~ ^10\. ]] || [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]] || \
       [[ "$ip" =~ ^192\.168\. ]] || [[ "$ip" =~ ^100\.(6[4-9]|[7-9][0-9]|1[0-2][0-7])\. ]]; then
        return
    fi

    [[ "$ip" =~ ^59\.43\. ]]                                                        && echo "CN2"    && return
    [[ "$ip" =~ ^202\.97\. ]]                                                       && echo "163"    && return
    [[ "$ip" =~ ^218\.105\. || "$ip" =~ ^210\.51\. ]]                               && echo "9929"   && return
    [[ "$ip" =~ ^219\.158\. ]]                                                      && echo "4837"   && return
    [[ "$ip" =~ ^209\.58\. || "$ip" =~ ^43\.252\. ]]                                && echo "CUG"    && return
    [[ "$ip" =~ ^223\.120\.(12[89]|1[3-9][0-9]|2[0-4][0-9]|25[0-5])\. ]]           && echo "CMIN2"  && return
    [[ "$ip" =~ ^223\.11[89]\. || "$ip" =~ ^223\.12[01]\. ]]                        && echo "CMI"    && return
    [[ "$ip" =~ ^221\.(17[6-9]|18[0-3])\. ]]                                       && echo "CMNET"  && return
}

# ============================================================
# 核心: 分析线路类型
# ============================================================
analyze_line_type() {
    local raw_data="$1"
    local isp_type="$2"
    local result="未识别"

    case "$isp_type" in
    "电信")
        if echo "$raw_data" | grep -qE "AS4809|59\.43\."; then
            if echo "$raw_data" | grep -qE "AS4134|202\.97\."; then
                result="CN2 GT    [优质线路]"
            else
                result="CN2 GIA   [顶级线路]"
            fi
        elif echo "$raw_data" | grep -qE "AS4134|202\.97\."; then
            result="电信163   [普通线路]"
        fi
        ;;
    "联通")
        if echo "$raw_data" | grep -qE "AS9929|218\.105\.|210\.51\."; then
            result="联通9929  [顶级线路]"
        elif echo "$raw_data" | grep -qE "AS10099|209\.58\.|43\.252\."; then
            if echo "$raw_data" | grep -qE "AS4837|219\.158\."; then
                result="CUG+4837  [优质线路]"
            else
                result="联通CUG   [顶级线路]"
            fi
        elif echo "$raw_data" | grep -qE "AS4837|219\.158\."; then
            result="联通4837  [普通线路]"
        elif echo "$raw_data" | grep -qE "AS4809|59\.43\."; then
            result="CN2转联通 [优质线路]"
        fi
        ;;
    "移动")
        if echo "$raw_data" | grep -qE "AS58807|223\.120\.(12[89]|1[3-9][0-9]|2[0-4][0-9]|25[0-5])\."; then
            result="移动CMIN2 [顶级线路]"
        elif echo "$raw_data" | grep -qE "AS58453|223\.11[89]\.|223\.12[01]\."; then
            result="移动CMI   [优质线路]"
        elif echo "$raw_data" | grep -qE "AS9808|221\.(17[6-9]|18[0-3])\."; then
            result="移动CMNET [普通线路]"
        elif echo "$raw_data" | grep -qE "AS4809|59\.43\."; then
            result="CN2转移动 [优质线路]"
        fi
        ;;
    esac

    echo "$result"
}

# ============================================================
# 提取详细路由路径: IP[标签] -> IP[标签] -> ...
# ============================================================
extract_route_path() {
    local raw_data="$1"
    local path=""

    while read -r ip; do
        [[ -z "$ip" ]] && continue
        [[ "$ip" =~ ^10\. ]] && continue
        [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]] && continue
        [[ "$ip" =~ ^192\.168\. ]] && continue
        [[ "$ip" =~ ^100\.(6[4-9]|[7-9][0-9]|1[0-2][0-7])\. ]] && continue

        local tag
        tag=$(identify_ip_tag "$ip")

        if [ -n "$tag" ]; then
            local entry="${ip}[${tag}]"
            if [ -z "$path" ]; then
                path="$entry"
            else
                path="${path} -> ${entry}"
            fi
        fi
    done < <(echo "$raw_data" | grep -oP '\d+\.\d+\.\d+\.\d+')

    [ -z "$path" ] && path="-"
    echo "$path"
}

# ============================================================
# 获取延迟
# ============================================================
get_latency() {
    local ip="$1"
    local lat
    lat=$(ping -c 3 -W 3 "$ip" 2>/dev/null | tail -1 | awk -F'/' '{printf "%.1f", $5}')
    [ -z "$lat" ] && lat="超时"
    echo "$lat"
}

# ============================================================
# 检测单个目标
# ============================================================
check_target() {
    local name="$1"
    local host="$2"

    local isp_type=""
    [[ "$name" == *"电信"* ]] && isp_type="电信"
    [[ "$name" == *"联通"* ]] && isp_type="联通"
    [[ "$name" == *"移动"* ]] && isp_type="移动"

    local ip
    ip=$(resolve_host "$host")

    local raw_data
    raw_data=$(get_trace_data "$ip")

    local line_type
    line_type=$(analyze_line_type "$raw_data" "$isp_type")

    local route_path
    route_path=$(extract_route_path "$raw_data")

    local latency
    latency=$(get_latency "$ip")

    local color="${WHITE}"
    case "$line_type" in
        *"顶级"*) color="${GREEN}" ;;
        *"优质"*) color="${YELLOW}" ;;
        *"普通"*) color="${RED}" ;;
    esac

    printf "  %-10s ${color}%-22s${NC}  延迟: %sms\n" \
           "$name" "$line_type" "$latency"
    echo -e "             ${CYAN}路径: ${NC}${route_path}"
    echo ""
}

# ============================================================
# 详细路由追踪
# ============================================================
detailed_trace() {
    local name="$1"
    local host="$2"

    local ip
    ip=$(resolve_host "$host")

    echo -e "\n${CYAN}===== ${name} (${ip}) =====${NC}"

    get_trace_data "$ip" | while IFS= read -r line; do
        if echo "$line" | grep -qP '59\.43\.'; then
            echo -e "${GREEN}${line}  <- CN2${NC}"
        elif echo "$line" | grep -qP '202\.97\.'; then
            echo -e "${RED}${line}  <- 163骨干${NC}"
        elif echo "$line" | grep -qP '218\.105\.|210\.51\.'; then
            echo -e "${GREEN}${line}  <- 联通9929${NC}"
        elif echo "$line" | grep -qP '219\.158\.'; then
            echo -e "${RED}${line}  <- 联通4837${NC}"
        elif echo "$line" | grep -qP '209\.58\.|43\.252\.'; then
            echo -e "${GREEN}${line}  <- 联通CUG${NC}"
        elif echo "$line" | grep -qP '223\.120\.(12[89]|1[3-9][0-9]|2[0-4][0-9]|25[0-5])\.'; then
            echo -e "${GREEN}${line}  <- CMIN2${NC}"
        elif echo "$line" | grep -qP '223\.11[89]\.|223\.12[01]\.'; then
            echo -e "${YELLOW}${line}  <- CMI${NC}"
        elif echo "$line" | grep -qP '221\.(17[6-9]|18[0-3])\.'; then
            echo -e "${RED}${line}  <- CMNET${NC}"
        else
            echo "$line"
        fi
    done
}

# ============================================================
# 菜单
# ============================================================
show_menu() {
    echo -e "${WHITE}请选择检测模式:${NC}"
    echo -e "  ${GREEN}1)${NC} 快速检测 - 显示线路类型和详细路径"
    echo -e "  ${GREEN}2)${NC} 详细检测 - 显示完整路由追踪"
    echo -e "  ${GREEN}3)${NC} 指定目标 - 选择单个目标检测"
    echo -e "  ${GREEN}0)${NC} 退出"
    echo ""
    read -rp "请输入选项 [1]: " choice < /dev/tty
    choice=${choice:-1}
}

# ============================================================
# 快速检测
# ============================================================
quick_test() {
    echo -e "\n${CYAN}[开始回程路由检测]${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    local total=${#ORDERED_KEYS[@]}
    local current=0
    local last_city=""

    for key in "${ORDERED_KEYS[@]}"; do
        ((current++))

        local city
        city=$(echo "$key" | grep -oP '^.{2}')
        if [ -n "$last_city" ] && [ "$city" != "$last_city" ]; then
            echo -e "${CYAN}  ──────────────────────────────────────────────────────────────────${NC}"
        fi
        last_city="$city"

        check_target "$key" "${TARGETS[$key]}"
    done

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  线路等级:"
    echo -e "    电信: ${GREEN}CN2 GIA [顶级]${NC} > ${YELLOW}CN2 GT [优质]${NC} > ${RED}电信163 [普通]${NC}"
    echo -e "    联通: ${GREEN}9929/CUG [顶级]${NC} > ${YELLOW}CUG+4837 [优质]${NC} > ${RED}4837 [普通]${NC}"
    echo -e "    移动: ${GREEN}CMIN2 [顶级]${NC} > ${YELLOW}CMI [优质]${NC} > ${RED}CMNET [普通]${NC}"
    echo ""
}

# ============================================================
# 详细检测
# ============================================================
detailed_test() {
    echo -e "\n${CYAN}[开始详细路由追踪]${NC}"

    for key in "${ORDERED_KEYS[@]}"; do
        detailed_trace "$key" "${TARGETS[$key]}"
    done

    echo ""
}

# ============================================================
# 单个目标
# ============================================================
single_test() {
    echo ""
    local idx=1
    for key in "${ORDERED_KEYS[@]}"; do
        echo -e "  ${GREEN}${idx})${NC} ${key}"
        ((idx++))
    done
    echo ""
    read -rp "请选择目标 [1-9]: " sel < /dev/tty

    if [ "$sel" -ge 1 ] && [ "$sel" -le 9 ] 2>/dev/null; then
        local selected_key="${ORDERED_KEYS[$((sel-1))]}"
        local selected_target="${TARGETS[$selected_key]}"

        echo -e "\n${CYAN}[检测 ${selected_key}]${NC}"
        check_target "$selected_key" "$selected_target"
        detailed_trace "$selected_key" "$selected_target"
    else
        echo -e "${RED}无效选择${NC}"
    fi
}

# ============================================================
# 主程序
# ============================================================
main() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${YELLOW}[!] 建议以 root 权限运行: sudo $0${NC}"
        echo ""
    fi

    print_banner
    install_dependencies
    show_menu

    case "$choice" in
        1) quick_test ;;
        2) detailed_test ;;
        3) single_test ;;
        0) echo "退出"; exit 0 ;;
        *) echo -e "${RED}无效选项, 执行快速检测${NC}"; quick_test ;;
    esac

    echo -e "${GREEN}[✓] 检测完成！${NC}"
}

main "$@"
