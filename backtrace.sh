#!/bin/bash
# ============================================================
# VPS 回程线路检测脚本 v2.8.1
# 检测到北京/上海/广州三网回程路由类型
# 支持 nexttrace / besttrace / mtr / traceroute 多工具降级
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

TRACE_TOOL=""
PKG_INSTALL=""

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

extract_ipv4() {
    grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1
}

extract_asn() {
    grep -Eio 'AS[0-9]+' | head -1 | tr '[:lower:]' '[:upper:]'
}

download_file() {
    local url="$1"
    local output="$2"
    curl -fsSL --connect-timeout 10 --retry 2 --retry-delay 1 "$url" -o "$output" 2>/dev/null
}

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
# 海外运营商 ASN 映射
# ============================================================
declare -A OVERSEAS_ASN_MAP
OVERSEAS_ASN_MAP=(
    # 国际 Tier1 / 大型运营商
    [174]="Cogent"
    [1299]="Telia"
    [2914]="NTT"
    [3257]="GTT"
    [3356]="Lumen"
    [6461]="Zayo"
    [6762]="Sparkle"
    [6939]="HE"
    [701]="Verizon"
    [7922]="Comcast"
    [6453]="Tata"
    [1273]="Vodafone"
    [5511]="Orange"
    [3320]="DTAG"
    [9002]="RETN"
    [12389]="Rostelecom"
    # 亚太运营商
    [3491]="PCCW"
    [4760]="HKT"
    [9269]="HKBN"
    [9304]="HGC"
    [4637]="Telstra"
    [7473]="SingTel"
    [2497]="IIJ"
    [17676]="SoftBank"
    [4788]="TMNet"
    [7713]="Telkom"
    [23764]="CTGNet"
    [38001]="NewMedia"
    [58511]="Anycast"
    [131477]="Scloud"
    [55720]="GigsGigs"
    [906]="DMIT"
    [54574]="DMIT"
    # VPS / 云 / CDN
    [13335]="Cloudflare"
    [15169]="Google"
    [16509]="AWS"
    [14061]="DigitalOcean"
    [20473]="Vultr"
    [63949]="Linode"
    [16276]="OVH"
    [24940]="Hetzner"
    [9009]="M247"
    [25820]="IT7"
    [36352]="AS-COLOCROSSING"
    [21859]="Zenlayer"
    [35916]="Multacom"
    [46844]="ST"
    [40065]="CNSERVERS"
    # 国内出海口 (也可能在海外段出现)
    [10099]="CUG"
    [58453]="CMI"
    [58807]="CMIN2"
    [4809]="CN2"
)


# ============================================================
# 线路识别规则库 (更新 ASN / IP 段优先改这里)
# ============================================================
LINE_TAGS="CN2 163 9929 CUG 4837 CMIN2 CMI CMNET"

declare -A LINE_ASN_MAP
LINE_ASN_MAP=(
    # 电信
    [4809]="CN2"
    [4134]="163"
    # 联通
    [9929]="9929"
    [10099]="CUG"
    [4837]="4837"
    # 移动
    [58807]="CMIN2"
    [58453]="CMI"
    [9808]="CMNET"
)

LINE_IP_RULES=(
    # 电信
    "CN2|^59\\.43\\."
    "163|^202\\.97\\."
    # 联通
    "9929|^218\\.105\\.|^210\\.51\\."
    "CUG|^209\\.58\\.|^43\\.252\\.|^202\\.77\\.23\\."
    "4837|^219\\.158\\."
    # 移动
    "CMIN2|^223\\.120\\.(12[89]|1[3-9][0-9]|2[0-4][0-9]|25[0-5])\\."
    "CMI|^223\\.11[89]\\.|^223\\.12[01]\\."
    "CMNET|^221\\.(17[6-9]|18[0-3])\\."
)

# ============================================================
# 海外运营商 IP 段识别 (常见骨干网 IP 段)
# ============================================================
identify_overseas_ip() {
    local ip="$1"

    # PCCW
    [[ "$ip" =~ ^63\.218\. || "$ip" =~ ^63\.223\. || "$ip" =~ ^32\.130\. ]]        && echo "PCCW"     && return
    # NTT
    [[ "$ip" =~ ^129\.250\. || "$ip" =~ ^128\.241\. ]]                              && echo "NTT"      && return
    # GTT
    [[ "$ip" =~ ^213\.200\. || "$ip" =~ ^89\.149\. || "$ip" =~ ^77\.67\. ]]         && echo "GTT"      && return
    # Telia
    [[ "$ip" =~ ^62\.115\. || "$ip" =~ ^80\.91\. || "$ip" =~ ^213\.248\. ]]         && echo "Telia"    && return
    # Cogent
    [[ "$ip" =~ ^154\.54\. || "$ip" =~ ^66\.28\. || "$ip" =~ ^38\.140\. ]]          && echo "Cogent"   && return
    # Lumen / Level3
    [[ "$ip" =~ ^4\.6[89]\. || "$ip" =~ ^4\.7[0-9]\. ]]                             && echo "Lumen"    && return
    # HE
    [[ "$ip" =~ ^184\.104\. || "$ip" =~ ^184\.105\. || "$ip" =~ ^100\.100\. ]]      && echo "HE"       && return
    # Zayo
    [[ "$ip" =~ ^64\.125\. ]]                                                        && echo "Zayo"     && return
    # Sparkle
    [[ "$ip" =~ ^89\.221\. ]]                                                        && echo "Sparkle"  && return
    # Tata
    [[ "$ip" =~ ^80\.231\. ]]                                                        && echo "Tata"     && return
    # HKT
    [[ "$ip" =~ ^203\.215\. ]]                                                       && echo "HKT"      && return
    # HKBN
    [[ "$ip" =~ ^203\.186\. ]]                                                       && echo "HKBN"     && return
    # HGC
    [[ "$ip" =~ ^218\.189\. ]]                                                       && echo "HGC"      && return
    # SingTel
    [[ "$ip" =~ ^203\.208\. ]]                                                       && echo "SingTel"  && return
    # IIJ
    [[ "$ip" =~ ^210\.130\. ]]                                                       && echo "IIJ"      && return
    # Telstra
    [[ "$ip" =~ ^202\.84\. ]]                                                        && echo "Telstra"  && return
    # CTGNet
    [[ "$ip" =~ ^69\.194\. || "$ip" =~ ^103\.117\.2[0-5]\. ]]                       && echo "CTGNet"   && return
    # SoftBank
    [[ "$ip" =~ ^126\.0\. ]]                                                         && echo "SoftBank" && return
    # RETN
    [[ "$ip" =~ ^87\.245\. ]]                                                        && echo "RETN"     && return
    # DTAG
    [[ "$ip" =~ ^62\.157\. ]]                                                        && echo "DTAG"     && return
    # Vodafone
    [[ "$ip" =~ ^212\.43\. ]]                                                        && echo "Vodafone" && return
    # Orange
    [[ "$ip" =~ ^193\.251\. ]]                                                       && echo "Orange"   && return
}

# ============================================================
# 国内 IP 段判断
# ============================================================
is_cn_ip() {
    local ip="$1"
    identify_cn_tag "$ip" >/dev/null
}

is_private_ip() {
    local ip="$1"
    [[ "$ip" =~ ^10\. ]]          && return 0
    [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]] && return 0
    [[ "$ip" =~ ^192\.168\. ]]    && return 0
    [[ "$ip" =~ ^100\.(6[4-9]|[7-9][0-9]|1[0-2][0-7])\. ]] && return 0
    [[ "$ip" =~ ^127\. ]]         && return 0
    return 1
}

# ============================================================
# Banner
# ============================================================
print_banner() {
    [ -n "${TERM:-}" ] && [ "${TERM:-}" != "dumb" ] && clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║              VPS 回程线路检测脚本 v2.8.1                  ║"
    echo "║          检测三网回程路由 & 线路类型识别                 ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "  检测时间: ${WHITE}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "  主机名称: ${WHITE}$(hostname)${NC}"
    echo -e "  系统信息: ${WHITE}$(uname -r)${NC}"

    echo -e "${YELLOW}[*] 获取本机 IP 信息...${NC}"
    local ipinfo
    ipinfo=$(curl -fsSL --connect-timeout 5 https://ipinfo.io 2>/dev/null || true)

    if [ -n "$ipinfo" ] && echo "$ipinfo" | grep -q '"ip"'; then
        local ip org country city
        ip=$(printf '%s\n' "$ipinfo" | sed -nE 's/.*"ip"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -1)
        org=$(printf '%s\n' "$ipinfo" | sed -nE 's/.*"org"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -1)
        country=$(printf '%s\n' "$ipinfo" | sed -nE 's/.*"country"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -1)
        city=$(printf '%s\n' "$ipinfo" | sed -nE 's/.*"city"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -1)

        echo -e "  公网  IP: ${WHITE}${ip}${NC}"
        echo -e "  运营商  : ${WHITE}${org}${NC}"
        echo -e "  位置    : ${WHITE}${city}, ${country}${NC}"
    else
        local pub_ip
        pub_ip=$(curl -fsSL --connect-timeout 5 ip.sb 2>/dev/null || echo "获取失败")
        echo -e "  公网  IP: ${WHITE}${pub_ip}${NC}"
        echo -e "  运营商  : ${WHITE}获取失败${NC}"
    fi
    echo ""
}

# ============================================================
# 安装 nexttrace
# ============================================================
install_nexttrace() {
    local arch
    arch=$(uname -m)
    case $arch in
        x86_64)  arch="amd64" ;;
        aarch64) arch="arm64" ;;
        armv7l)  arch="armv7" ;;
    esac

    local urls=(
        "https://github.com/nxtrace/NTrace-core/releases/latest/download/nexttrace_linux_${arch}"
        "https://mirror.ghproxy.com/https://github.com/nxtrace/NTrace-core/releases/latest/download/nexttrace_linux_${arch}"
        "https://gh-proxy.com/https://github.com/nxtrace/NTrace-core/releases/latest/download/nexttrace_linux_${arch}"
    )

    for url in "${urls[@]}"; do
        echo -e "${YELLOW}    尝试: ${url}${NC}"
        if download_file "$url" /usr/local/bin/nexttrace; then
            chmod +x /usr/local/bin/nexttrace
            if /usr/local/bin/nexttrace --version &>/dev/null; then
                echo -e "${GREEN}    [✓] nexttrace 安装成功${NC}"
                return 0
            fi
        fi
    done

    rm -f /usr/local/bin/nexttrace
    echo -e "${RED}    [✗] nexttrace 所有下载源均失败${NC}"
    return 1
}

# ============================================================
# 安装 besttrace
# ============================================================
install_besttrace() {
    local arch
    arch=$(uname -m)

    local url=""
    case $arch in
        x86_64)  url="https://cdn.ipip.net/17mon/besttrace4linux.zip" ;;
        aarch64) url="https://cdn.ipip.net/17mon/besttrace4linux_arm.zip" ;;
    esac

    if [ -z "$url" ]; then
        echo -e "${RED}    [✗] besttrace 不支持当前架构: ${arch}${NC}"
        return 1
    fi

    echo -e "${YELLOW}    下载 besttrace...${NC}"
    local tmpdir
    tmpdir=$(mktemp -d)

    if download_file "$url" "${tmpdir}/besttrace.zip"; then
        if ! has_cmd unzip && [ -n "$PKG_INSTALL" ]; then
            $PKG_INSTALL unzip >/dev/null 2>&1 || true
        fi
        if has_cmd unzip; then
            unzip -q "${tmpdir}/besttrace.zip" -d "${tmpdir}/" 2>/dev/null
            local bt_bin
            bt_bin=$(find "${tmpdir}" -name "besttrace*" -type f ! -name "*.zip" | head -1)
            if [ -n "$bt_bin" ]; then
                cp "$bt_bin" /usr/local/bin/besttrace
                chmod +x /usr/local/bin/besttrace
                rm -rf "$tmpdir"
                echo -e "${GREEN}    [✓] besttrace 安装成功${NC}"
                return 0
            fi
        fi
    fi

    rm -rf "$tmpdir"
    echo -e "${RED}    [✗] besttrace 安装失败${NC}"
    return 1
}

# ============================================================
# 检查依赖 & 选择追踪工具
# ============================================================
install_dependencies() {
    echo -e "${YELLOW}[*] 检查可用追踪工具...${NC}"

    if has_cmd apt-get; then
        PKG_INSTALL="apt-get install -y"
    elif has_cmd yum; then
        PKG_INSTALL="yum install -y"
    elif has_cmd dnf; then
        PKG_INSTALL="dnf install -y"
    elif has_cmd pacman; then
        PKG_INSTALL="pacman -S --noconfirm"
    fi

    echo -e "${YELLOW}[*] 选择路由追踪工具...${NC}"

    # 默认优先使用系统自带/已安装工具，避免 nexttrace API 限制。
    if has_cmd tracepath; then
        TRACE_TOOL="tracepath"
        echo -e "${GREEN}[✓] 使用 tracepath (无需安装 / 无 API 限制)${NC}"
    elif has_cmd traceroute; then
        TRACE_TOOL="traceroute"
        echo -e "${GREEN}[✓] 使用 traceroute${NC}"
    elif has_cmd mtr; then
        TRACE_TOOL="mtr"
        echo -e "${GREEN}[✓] 使用 mtr${NC}"
    elif has_cmd nexttrace && nexttrace --version &>/dev/null; then
        TRACE_TOOL="nexttrace"
        echo -e "${YELLOW}[✓] 使用 nexttrace (备用)${NC}"
    elif has_cmd besttrace; then
        TRACE_TOOL="besttrace"
        echo -e "${YELLOW}[✓] 使用 besttrace (备用)${NC}"
    elif [ -n "$PKG_INSTALL" ]; then
        echo -e "${YELLOW}[*] 未找到可用工具，尝试安装 traceroute...${NC}"
        $PKG_INSTALL traceroute >/dev/null 2>&1 || true
        if has_cmd traceroute; then
            TRACE_TOOL="traceroute"
            echo -e "${GREEN}[✓] 使用 traceroute${NC}"
        fi
    fi

    if ! has_cmd dig && ! has_cmd getent && ! has_cmd host && [ -n "$PKG_INSTALL" ]; then
        echo -e "${YELLOW}[*] 安装 DNS 查询工具...${NC}"
        $PKG_INSTALL dnsutils >/dev/null 2>&1 || $PKG_INSTALL bind-utils >/dev/null 2>&1 || true
    fi

    if [ -z "$TRACE_TOOL" ]; then
        echo -e "${RED}[✗] 无可用追踪工具，请安装 tracepath / traceroute / mtr 任意一个${NC}"
        exit 1
    fi

    echo -e "${GREEN}[✓] 工具检查完成 (追踪工具: ${TRACE_TOOL})${NC}"
    echo ""
}

# ============================================================
# DNS 解析
# ============================================================
resolve_host() {
    local host="$1"
    local ip
    if has_cmd dig; then
        ip=$(dig +short "$host" 2>/dev/null | extract_ipv4)
    fi
    if [ -z "$ip" ] && has_cmd getent; then
        ip=$(getent hosts "$host" 2>/dev/null | awk '{print $1}' | extract_ipv4)
    fi
    if [ -z "$ip" ] && has_cmd host; then
        ip=$(host "$host" 2>/dev/null | extract_ipv4)
    fi
    [ -z "$ip" ] && ip="$host"
    echo "$ip"
}

# ============================================================
# 获取路由原始数据
# ============================================================
get_trace_data() {
    local ip="$1"
    case "$TRACE_TOOL" in
        nexttrace)
            nexttrace -q 1 -n "$ip" 2>/dev/null
            ;;
        besttrace)
            besttrace -q 1 -g cn "$ip" 2>/dev/null
            ;;
        mtr)
            mtr -z -r -n -c 1 "$ip" 2>/dev/null
            ;;
        tracepath)
            tracepath -n -m 20 "$ip" 2>/dev/null
            ;;
        traceroute)
            if traceroute --help 2>&1 | grep -q '\-A'; then
                traceroute -A -n -q 1 -m 30 -w 2 "$ip" 2>/dev/null
            else
                traceroute -n -q 1 -m 30 -w 2 "$ip" 2>/dev/null
            fi
            ;;
    esac
}

# ============================================================
# 识别国内 IP 标签
# ============================================================
identify_cn_tag() {
    local ip="$1"
    local rule tag regex
    is_private_ip "$ip" && return

    for rule in "${LINE_IP_RULES[@]}"; do
        tag="${rule%%|*}"
        regex="${rule#*|}"
        if [[ "$ip" =~ $regex ]]; then
            echo "$tag"
            return
        fi
    done
}

# ============================================================
# 从 ASN 识别 (国内 + 海外)
# ============================================================
identify_asn_tag() {
    local asn="$1"
    asn="${asn#AS}"
    asn="${asn#as}"

    # 国内 ASN
    if [ -n "${LINE_ASN_MAP[$asn]}" ]; then
        echo "${LINE_ASN_MAP[$asn]}"
        return
    fi

    # 海外 ASN
    if [ -n "${OVERSEAS_ASN_MAP[$asn]}" ]; then
        echo "${OVERSEAS_ASN_MAP[$asn]}"
        return
    fi
}

is_line_tag() {
    case " $LINE_TAGS " in
        *" $1 "*) return 0 ;;
        *) return 1 ;;
    esac
}

format_node() {
    local ip="$1"
    local tag="$2"

    if [ -z "$ip" ]; then
        echo "*"
    elif [ -n "$tag" ]; then
        echo "${ip}[${tag}]"
    else
        echo "$ip"
    fi
}

format_line_node() {
    local raw_data="$1"
    local preferred_tags="$2"
    local fallback_ip=""
    local fallback_tag=""

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        local ip
        ip=$(echo "$line" | extract_ipv4)
        [[ -z "$ip" ]] && continue
        is_private_ip "$ip" && continue

        local tag
        tag=$(identify_cn_tag "$ip")

        if [ -z "$tag" ]; then
            local asn
            asn=$(echo "$line" | extract_asn)
            [ -n "$asn" ] && tag=$(identify_asn_tag "$asn")
        fi

        if is_line_tag "$tag"; then
            [ -z "$fallback_ip" ] && fallback_ip="$ip" && fallback_tag="$tag"
            case " $preferred_tags " in
                *" $tag "*) format_node "$ip" "$tag"; return ;;
            esac
        fi
    done <<< "$raw_data"

    format_node "$fallback_ip" "$fallback_tag"
}

line_preferred_tags() {
    local line_type="$1"
    case "$line_type" in
        *"CN2"*) echo "CN2" ;;
        *"电信163"*) echo "163" ;;
        *"9929"*) echo "9929" ;;
        *"CUG"*) echo "CUG 4837" ;;
        *"4837"*) echo "4837" ;;
        *"CMIN2"*) echo "CMIN2" ;;
        *"CMI"*) echo "CMI" ;;
        *"CMNET"*) echo "CMNET" ;;
        *) echo "CN2 163 9929 CUG 4837 CMIN2 CMI CMNET" ;;
    esac
}

# ============================================================
# 识别海外 IP 的运营商 (IP段 + ASN 双维度)
# ============================================================
get_overseas_tag() {
    local ip="$1"
    local line="$2"

    # 先从 IP 段识别
    local tag
    tag=$(identify_overseas_ip "$ip")
    if [ -n "$tag" ]; then
        echo "$tag"
        return
    fi

    # 再从 ASN 识别
    local asn
    asn=$(echo "$line" | extract_asn)
    if [ -n "$asn" ]; then
        asn="${asn#AS}"
        if [ -n "${OVERSEAS_ASN_MAP[$asn]}" ]; then
            echo "${OVERSEAS_ASN_MAP[$asn]}"
            return
        fi
    fi
}


trace_has_tag() {
    local raw_data="$1"
    local target_tag="$2"

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        local ip tag asn
        ip=$(echo "$line" | extract_ipv4)
        [ -n "$ip" ] && tag=$(identify_cn_tag "$ip")

        if [ -z "$tag" ]; then
            asn=$(echo "$line" | extract_asn)
            [ -n "$asn" ] && tag=$(identify_asn_tag "$asn")
        fi

        [ "$tag" = "$target_tag" ] && return 0
    done <<< "$raw_data"

    return 1
}

# ============================================================
# 分析线路类型
# ============================================================
analyze_line_type() {
    local raw_data="$1"
    local isp_type="$2"
    local result="未识别"

    case "$isp_type" in
    "电信")
        if trace_has_tag "$raw_data" "CN2"; then
            if trace_has_tag "$raw_data" "163"; then
                result="CN2 GT [优质线路]"
            else
                result="CN2 GIA [顶级线路]"
            fi
        elif trace_has_tag "$raw_data" "163"; then
            result="电信163 [优质线路]"
        fi
        ;;
    "联通")
        if trace_has_tag "$raw_data" "9929"; then
            result="联通9929 [顶级线路]"
        elif trace_has_tag "$raw_data" "CUG"; then
            if trace_has_tag "$raw_data" "4837"; then
                result="CUG+4837 [优质线路]"
            else
                result="联通CUG [优质线路]"
            fi
        elif trace_has_tag "$raw_data" "4837"; then
            result="联通4837 [普通线路]"
        elif trace_has_tag "$raw_data" "CN2"; then
            result="CN2转联通 [优质线路]"
        fi
        ;;
    "移动")
        if trace_has_tag "$raw_data" "CMIN2"; then
            result="移动CMIN2 [顶级线路]"
        elif trace_has_tag "$raw_data" "CMI"; then
            result="移动CMI [优质线路]"
        elif trace_has_tag "$raw_data" "CMNET"; then
            result="移动CMNET [普通线路]"
        elif trace_has_tag "$raw_data" "CN2"; then
            result="CN2转移动 [优质线路]"
        fi
        ;;
    esac

    echo "$result"
}

# ============================================================
# 提取判断线路的关键节点
# ============================================================
extract_key_hops() {
    local raw_data="$1"
    local line_type="$2"
    local preferred_tags
    preferred_tags=$(line_preferred_tags "$line_type")

    format_line_node "$raw_data" "$preferred_tags"
}

# ============================================================
# 获取延迟
# ============================================================
get_latency() {
    local ip="$1"
    local lat

    if ! has_cmd ping; then
        echo "超时"
        return
    fi

    lat=$(ping -c 3 -W 3 "$ip" 2>/dev/null | awk -F'/' '/^rtt|^round-trip/ {printf "%.1f", $5}')
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

    local key_hops
    key_hops=$(extract_key_hops "$raw_data" "$line_type")

    local latency
    latency=$(get_latency "$ip")
    local latency_display="$latency"
    [ "$latency" != "超时" ] && latency_display="${latency}ms"

    local color="${WHITE}"
    local level_icon="○"
    case "$line_type" in
        *"顶级"*) color="${GREEN}"; level_icon="★" ;;
        *"优质"*) color="${YELLOW}"; level_icon="◆" ;;
        *"普通"*) color="${RED}"; level_icon="△" ;;
    esac

    printf "  %-8s ${color}%-2s %-20s${NC}  %-9s  %s\n" \
           "$name" "$level_icon" "$line_type" "$latency_display" "$key_hops"
}

# ============================================================
# 详细路由追踪
# ============================================================
detailed_trace() {
    local name="$1"
    local host="$2"

    local ip
    ip=$(resolve_host "$host")

    echo -e "\n${CYAN}===== ${name} (${ip}) [${TRACE_TOOL}] =====${NC}"

    get_trace_data "$ip" | while IFS= read -r line; do
        # 提取 IP 和 ASN
        local hop_ip
        hop_ip=$(echo "$line" | extract_ipv4)

        local label=""

        # 国内标签
        if [ -n "$hop_ip" ]; then
            label=$(identify_cn_tag "$hop_ip")
        fi

        # ASN 标签
        if [ -z "$label" ]; then
            local asn
            asn=$(echo "$line" | extract_asn)
            [ -n "$asn" ] && label=$(identify_asn_tag "$asn")
        fi

        # 海外 IP 标签
        if [ -z "$label" ] && [ -n "$hop_ip" ] && ! is_private_ip "$hop_ip"; then
            label=$(identify_overseas_ip "$hop_ip")
        fi

        # 着色输出
        if [ -n "$label" ]; then
            case "$label" in
                CN2|9929|CUG|CMIN2)
                    echo -e "${GREEN}${line}  <- ${label}${NC}" ;;
                CMI|Telia|NTT|PCCW|HKT|CTGNet)
                    echo -e "${YELLOW}${line}  <- ${label}${NC}" ;;
                163|4837|CMNET)
                    echo -e "${RED}${line}  <- ${label}${NC}" ;;
                *)
                    echo -e "${BLUE}${line}  <- ${label}${NC}" ;;
            esac
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
    echo -e "  ${GREEN}1)${NC} 快速检测 - 显示线路类型、延迟和判断节点"
    echo -e "  ${GREEN}2)${NC} 详细检测 - 显示完整路由追踪"
    echo -e "  ${GREEN}3)${NC} 指定目标 - 选择单个目标检测"
    echo -e "  ${GREEN}0)${NC} 退出"
    echo ""

    if [ -t 0 ]; then
        read -rp "请输入选项 [1]: " choice
    elif [ -t 1 ] && [ -r /dev/tty ]; then
        read -rp "请输入选项 [1]: " choice < /dev/tty
    else
        choice=1
        echo -e "${YELLOW}[!] 未检测到交互终端，默认执行快速检测${NC}"
    fi
    choice=${choice:-1}
}

# ============================================================
# 快速检测
# ============================================================
quick_test() {
    echo -e "\n${CYAN}回程路由检测${NC}  ${WHITE}${TRACE_TOOL}${NC}"
    echo -e "${CYAN}────────────────────────────────────────────────────────────────────────────${NC}"
    printf "  %-8s %-24s %-9s %s\n" "目标" "线路" "延迟" "判断节点"
    echo -e "${CYAN}────────────────────────────────────────────────────────────────────────────${NC}"

    local last_city=""

    for key in "${ORDERED_KEYS[@]}"; do
        local city
        city=${key:0:2}
        if [ -n "$last_city" ] && [ "$city" != "$last_city" ]; then
            echo -e "${CYAN}  ─────────────────────────────────────────────────────────────────────────${NC}"
        fi
        last_city="$city"

        check_target "$key" "${TARGETS[$key]}"
    done

    echo -e "${CYAN}────────────────────────────────────────────────────────────────────────────${NC}"
    echo ""
    echo -e "  图例: ${GREEN}★ 顶级线路${NC}  ${YELLOW}◆ 优质线路${NC}  ${RED}△ 普通线路${NC}"
    echo -e "  判断节点: 仅显示用于识别线路的关键节点"
    echo ""
}

# ============================================================
# 详细检测
# ============================================================
detailed_test() {
    echo -e "\n${CYAN}[开始详细路由追踪] (工具: ${TRACE_TOOL})${NC}"

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
    if [ -t 0 ]; then
        read -rp "请选择目标 [1-9]: " sel
    elif [ -t 1 ] && [ -r /dev/tty ]; then
        read -rp "请选择目标 [1-9]: " sel < /dev/tty
    else
        sel=1
        echo -e "${YELLOW}[!] 未检测到交互终端，默认选择 1${NC}"
    fi

    if [ "$sel" -ge 1 ] && [ "$sel" -le 9 ] 2>/dev/null; then
        local selected_key="${ORDERED_KEYS[$((sel-1))]}"
        local selected_target="${TARGETS[$selected_key]}"

        echo -e "\n${CYAN}[检测 ${selected_key}] (工具: ${TRACE_TOOL})${NC}"
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

if ! (return 0 2>/dev/null); then
    main "$@"
fi
