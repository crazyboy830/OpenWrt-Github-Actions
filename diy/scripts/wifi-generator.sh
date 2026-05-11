#!/bin/bash
# diy/scripts/wifi-generator.sh - OpenWrt 智能 WiFi 配置生成器
# 功能: 根据 MAC 地址 + 频段生成唯一 SSID，支持自定义前缀/密码
# 用法: ./wifi-generator.sh --prefix "MyWiFi_" --password "mypass123" > wireless

set -euo pipefail

# 📋 默认参数
WIFI_PREFIX="${WIFI_PREFIX:-OpenWrt_}"
WIFI_PASSWORD="${WIFI_PASSWORD:-1234567890}"
COUNTRY_CODE="${COUNTRY_CODE:-CN}"
OUTPUT_FILE=""

# 🎨 颜色输出
RED='\033[0;31m' GREEN='\033[0;32m' NC='\033[0m'
info() { echo -e "${GREEN}[✓]${NC} $1" >&2; }
warn() { echo -e "${YELLOW}[!]${NC} $1" >&2; }

# 🔍 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --prefix) WIFI_PREFIX="$2"; shift 2 ;;
        --password) WIFI_PASSWORD="$2"; shift 2 ;;
        --country) COUNTRY_CODE="$2"; shift 2 ;;
        --output) OUTPUT_FILE="$2"; shift 2 ;;
        --help) 
            echo "用法: $0 [选项]"
            echo "选项:"
            echo "  --prefix PREFIX   WiFi 名称前缀 (默认: OpenWrt_)"
            echo "  --password PASS   WiFi 密码 (默认: 1234567890)"
            echo "  --country CODE    国家码 (默认: CN)"
            echo "  --output FILE     输出文件 (默认: stdout)"
            exit 0 ;;
        *) shift ;;
    esac
done

# 🔧 生成 MAC 后缀（模拟运行时获取）
# ⚠️  实际在路由器上执行时会替换为真实 MAC
generate_mac_suffix() {
    # 🎲 开发模式：使用随机后缀（避免冲突）
    if [ "${DRY_RUN:-false}" = "true" ]; then
        echo "XXXX"
        return
    fi
    
    # 📡 生产模式：读取真实 MAC（需 root）
    local mac=$(cat /sys/class/ieee80211/phy0/macaddress 2>/dev/null | tr -d ':')
    echo "${mac: -4}"  # 取最后 4 位
}

# 📶 生成单 radio 配置
generate_radio_config() {
    local radio_idx="$1"
    local band="$2"      # 2g / 5g
    local path="$3"      # 硬件路径
    local htmode="$4"    # HE20 / HE80
    local channel="$5"   # auto / 具体信道
    
    local mac_suffix=$(generate_mac_suffix)
    local ssid="${WIFI_PREFIX}${mac_suffix}_${band^^}"  # XX_2G / XX_5G
    
    cat << EOF
config wifi-device 'radio${radio_idx}'
    option type 'mac80211'
    option path '${path}'
    option channel '${channel}'
    option band '${band}'
    option htmode '${htmode}'
    option country '${COUNTRY_CODE}'
    option cell_density '0'
    option disabled '0'

config wifi-iface 'default_radio${radio_idx}'
    option device 'radio${radio_idx}'
    option network 'lan'
    option mode 'ap'
    option ssid '${ssid}'
    option encryption 'psk2'
    option key '${WIFI_PASSWORD}'
    option isolate '0'
    option disassoc_low_ack '1'
EOF

    # 🚀 5G 频段额外优化
    if [ "$band" = "5g" ]; then
        cat << EOF
    # 📡 5G 优选信道（避开雷达信道）
    list channels '36' '40' '44' '48' '149' '153' '157' '161'
    # 🔄 启用 802.11k/v 快速漫游
    option ieee80211k '1'
    option ieee80211v '1'
EOF
    fi
    echo ""  # 空行分隔
}

# 🎯 主生成函数
generate_wireless_config() {
    echo "# /etc/config/wireless - 由 wifi-generator.sh 自动生成"
    echo "# 前缀: $WIFI_PREFIX | 国家码: $COUNTRY_CODE | 时间: $(date '+%Y-%m-%d %H:%M')"
    echo ""
    
    # 📡 假设双频设备（实际应通过 iwinfo 检测）
    # XDR6088: phy0=2.4G, phy1=5G
    generate_radio_config 0 "2g" "platform/soc/18000000.wifi" "HE20" "auto"
    generate_radio_config 1 "5g" "platform/soc/18000000.wifi+1" "HE80" "auto"
    
    # 🔐 全局设置
    cat << EOF
# 🌐 全局无线设置
config wifi-device 'radio0'
    option txpower '20'  # 2.4G 功率 (dBm)
config wifi-device 'radio1'
    option txpower '23'  # 5G 功率 (dBm)
EOF
}

# 🚀 执行输出
if [ -n "$OUTPUT_FILE" ]; then
    generate_wireless_config > "$OUTPUT_FILE"
    info "✅ 配置已写入: $OUTPUT_FILE"
    # 🔐 设置执行权限（供首次启动脚本调用）
    chmod +x "$OUTPUT_FILE" 2>/dev/null || true
else
    generate_wireless_config
fi
