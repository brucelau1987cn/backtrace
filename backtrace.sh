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
    [[ "$ip" =~ ^59\.43\. ]]       && return 0
    [[ "$ip" =~ ^202\.97\. ]]      && return 0
    [[ "$ip" =~ ^218\.105\. ]]     && return 0
    [[ "$ip" =~ ^210\.51\. ]]      && return 0
    [[ "$ip" =~ ^219\.158\. ]]     && return 0
    [[ "$ip" =~ ^223\.120\. ]]     && return 0
    [[ "$ip" =~ ^223\.11[89]\. ]]  && return 0
    [[ "$ip" =~ ^223\.121\. ]]     && return 0
    [[ "$ip" =~ ^221\.(17[6-9]|18[0-3])\. ]] && return 0
    return 1
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
# 安装依赖 & 选择追踪工具
# ============================================================
install_dependencies() {
    echo -e "${YELLOW}[*] 检查并安装必要工具...${NC}"

    if has_cmd apt-get; then
        PKG_INSTALL="apt-get install -y"
    elif has_cmd yum; then
        PKG_INSTALL="yum install -y"
    elif has_cmd dnf; then
        PKG_INSTALL="dnf install -y"
    elif has_cmd pacman; then
        PKG_INSTALL="pacman -S --noconfirm"
    fi

    if [ -z "$PKG_INSTALL" ]; then
        echo -e "${YELLOW}[!] 未识别包管理器，将仅使用系统已安装工具${NC}"
    fi

    if ! has_cmd traceroute && [ -n "$PKG_INSTALL" ]; then
        echo -e "${YELLOW}[*] 安装 traceroute...${NC}"
        $PKG_INSTALL traceroute >/dev/null 2>&1 || true
    fi

    if ! has_cmd mtr && [ -n "$PKG_INSTALL" ]; then
        echo -e "${YELLOW}[*] 安装 mtr...${NC}"
        $PKG_INSTALL mtr >/dev/null 2>&1 || true
    fi

    if ! has_cmd dig && ! has_cmd getent && ! has_cmd host && [ -n "$PKG_INSTALL" ]; then
        echo -e "${YELLOW}[*] 安装 DNS 查询工具...${NC}"
        $PKG_INSTALL dnsutils >/dev/null 2>&1 || $PKG_INSTALL bind-utils >/dev/null 2>&1 || true
    fi

    echo -e "${YELLOW}[*] 选择路由追踪工具...${NC}"

    if has_cmd nexttrace && nexttrace --version &>/dev/null; then
        TRACE_TOOL="nexttrace"
        echo -e "${GREEN}[✓] 使用 nexttrace${NC}"
    else
        echo -e "${YELLOW}[*] 尝试安装 nexttrace...${NC}"
        if install_nexttrace; then
            TRACE_TOOL="nexttrace"
        fi
    fi

    if [ -z "$TRACE_TOOL" ]; then
        if has_cmd besttrace; then
            TRACE_TOOL="besttrace"
            echo -e "${GREEN}[✓] 使用 besttrace${NC}"
        else
            echo -e "${YELLOW}[*] 尝试安装 besttrace...${NC}"
            if install_besttrace; then
                TRACE_TOOL="besttrace"
            fi
        fi
    fi

    if [ -z "$TRACE_TOOL" ]; then
        if has_cmd mtr; then
            TRACE_TOOL="mtr"
            echo -e "${YELLOW}[✓] 使用 mtr${NC}"
        fi
    fi

    if [ -z "$TRACE_TOOL" ]; then
        if has_cmd traceroute; then
            TRACE_TOOL="traceroute"
            echo -e "${YELLOW}[✓] 使用 traceroute${NC}"
        else
            echo -e "${RED}[✗] 无可用追踪工具${NC}"
            exit 1
        fi
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
    is_private_ip "$ip" && return

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
# 从 ASN 识别 (国内 + 海外)
# ============================================================
identify_asn_tag() {
    local asn="$1"
    asn="${asn#AS}"
    asn="${asn#as}"

    # 国内 ASN
    case "$asn" in
        4809)  echo "CN2"   ; return ;;
        4134)  echo "163"   ; return ;;
        9929)  echo "9929"  ; return ;;
        10099) echo "CUG"   ; return ;;
        4837)  echo "4837"  ; return ;;
        58807) echo "CMIN2" ; return ;;
        58453) echo "CMI"   ; return ;;
        9808)  echo "CMNET" ; return ;;
    esac

    # 海外 ASN
    if [ -n "${OVERSEAS_ASN_MAP[$asn]}" ]; then
        echo "${OVERSEAS_ASN_MAP[$asn]}"
        return
    fi
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

# ============================================================
# 分析线路类型
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
            result="电信163   [优化线路]"
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
# 提取关键节点: 国内口上一跳[运营商] -> 国内入口第一跳[线路]
# ============================================================
extract_key_hops() {
    local raw_data="$1"
    local prev_public_ip=""
    local prev_public_tag=""
    local pre_cn_ip=""
    local pre_cn_tag=""
    local first_cn_ip=""
    local first_cn_tag=""
    local found_cn=0

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        local ip
        ip=$(echo "$line" | extract_ipv4)
        [[ -z "$ip" ]] && continue
        is_private_ip "$ip" && continue

        # 尝试识别国内标签
        local cn_tag
        cn_tag=$(identify_cn_tag "$ip")

        # 没从 IP 识别出来, 再从 ASN 补充
        if [ -z "$cn_tag" ]; then
            local asn
            asn=$(echo "$line" | extract_asn)
            if [ -n "$asn" ]; then
                local asn_tag
                asn_tag=$(identify_asn_tag "$asn")
                # 只有国内标签才算国内节点
                case "$asn_tag" in
                    CN2|163|9929|CUG|4837|CMIN2|CMI|CMNET)
                        cn_tag="$asn_tag"
                        ;;
                esac
            fi
        fi

        if [ -n "$cn_tag" ] || is_cn_ip "$ip"; then
            # === 国内入口第一跳 ===
            if [ $found_cn -eq 0 ]; then
                pre_cn_ip="$prev_public_ip"
                pre_cn_tag="$prev_public_tag"
                first_cn_ip="$ip"
                first_cn_tag="${cn_tag:-CN}"
                found_cn=1
            fi
        else
            # === 国内口上一跳：第一个国内节点之前的最后一个公网节点 ===
            if [ $found_cn -eq 0 ]; then
                prev_public_ip="$ip"
                local o_tag
                o_tag=$(get_overseas_tag "$ip" "$line")
                prev_public_tag="$o_tag"
            fi
        fi
    done <<< "$raw_data"

    # 组合输出
    local pre_cn_str="*"
    local cn_str="*"

    if [ -n "$pre_cn_ip" ]; then
        if [ -n "$pre_cn_tag" ]; then
            pre_cn_str="${pre_cn_ip}[${pre_cn_tag}]"
        else
            pre_cn_str="${pre_cn_ip}"
        fi
    fi

    if [ -n "$first_cn_ip" ]; then
        cn_str="${first_cn_ip}[${first_cn_tag}]"
    fi

    echo "${pre_cn_str} -> ${cn_str}"
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
    key_hops=$(extract_key_hops "$raw_data")

    local latency
    latency=$(get_latency "$ip")
    local latency_display="$latency"
    [ "$latency" != "超时" ] && latency_display="${latency}ms"

    local color="${WHITE}"
    case "$line_type" in
        *"顶级"*) color="${GREEN}" ;;
        *"优质"*) color="${YELLOW}" ;;
        *"普通"*) color="${RED}" ;;
    esac

    printf "  %-10s ${color}%-22s${NC}  延迟: %-10s  入口: %s\n" \
           "$name" "$line_type" "$latency_display" "$key_hops"
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
    echo -e "  ${GREEN}1)${NC} 快速检测 - 显示线路类型和关键节点"
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
    echo -e "\n${CYAN}[开始回程路由检测] (工具: ${TRACE_TOOL})${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    local last_city=""

    for key in "${ORDERED_KEYS[@]}"; do
        local city
        city=${key:0:2}
        if [ -n "$last_city" ] && [ "$city" != "$last_city" ]; then
            echo -e "${CYAN}  ──────────────────────────────────────────────────────────────────────────────────────────${NC}"
        fi
        last_city="$city"

        check_target "$key" "${TARGETS[$key]}"
    done

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  线路等级:"
    echo -e "    电信: ${GREEN}CN2 GIA [顶级]${NC} > ${YELLOW}CN2 GT / 电信163 [优化]${NC} > ${RED}电信163 [普通]${NC}"
    echo -e "    联通: ${GREEN}9929/CUG [顶级]${NC} > ${YELLOW}CUG+4837 [优质]${NC} > ${RED}4837 [普通]${NC}"
    echo -e "    移动: ${GREEN}CMIN2 [顶级]${NC} > ${YELLOW}CMI [优质]${NC} > ${RED}CMNET [普通]${NC}"
    echo ""
    echo -e "  入口格式: 国内口上一跳[运营商] -> 国内入口第一跳[线路]"
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
