#!/bin/bash
# ============================================================================
# OpenWrt 官方源码自定义配置脚本 (适配版)
# 适配: openwrt/openwrt 官方源码 + kenzok8/small-package
# 注意: 官方源码与LEDE在包名、内核版本、配置上有差异
# ============================================================================
set -e

# 📋 接收环境变量
DEVICE="${DEVICE:-xdr6088}"
DEVICE_NAME="${DEVICE_NAME:-OpenWrt}"
WIFI_PREFIX="${WIFI_PREFIX:-OpenWrt_}"
WIFI_PASSWORD="${WIFI_PASSWORD:-1234567890}"
ENABLE_TRANSLATE="${ENABLE_TRANSLATE:-true}"
ENABLE_KERNEL_SYNC="${ENABLE_KERNEL_SYNC:-false}"
SKIP_FEEDS_MODIFY="${SKIP_FEEDS_MODIFY:-false}"
CONFIG_VERSION="${CONFIG_VERSION:-full}"

OPENWRT_PATH="${OPENWRT_PATH:-$PWD}"
GITHUB_WORKSPACE="${GITHUB_WORKSPACE:-$(cd "$(dirname "$0")/.."; pwd)}"
SCRIPTS_DIR="${SCRIPTS_DIR:-$GITHUB_WORKSPACE/diy/scripts}"

cd "$OPENWRT_PATH"

# 🎨 日志函数
log_info() { echo -e "\033[0;32m[✓]\033[0m $1"; }
log_warn() { echo -e "\033[1;33m[!]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[✗]\033[0m $1"; }

# ============================================================================
# 🔧 模块 0: 加载辅助脚本
# ============================================================================
load_helpers() {
    log_info "🔧 加载辅助脚本..."
    [ -f "$SCRIPTS_DIR/translate-map.sh" ] && source "$SCRIPTS_DIR/translate-map.sh" && log_info "  ✓ translate-map.sh"
    [ -f "$SCRIPTS_DIR/conflict-resolver.sh" ] && source "$SCRIPTS_DIR/conflict-resolver.sh" && log_info "  ✓ conflict-resolver.sh"
}

# ============================================================================
# 🔧 模块 1: 配置 feeds (仅添加 kenzok8/small-package)
# ============================================================================
configure_feeds() {
    [ "$SKIP_FEEDS_MODIFY" = "true" ] && { log_info "⏭️ 跳过 feeds"; return 0; }
    log_info "📡 配置插件源 (仅添加 kenzok8/small-package)..."
    
    # 安全添加 feed 函数
    safe_add() {
        grep -q "^src-git $1 " feeds.conf.default 2>/dev/null || echo "src-git $1 $2" >> feeds.conf.default
    }
    
    # 只添加 kenzok8/small-package，移除其他第三方源
    safe_add "small" "https://github.com/kenzok8/small;master"
    
    # 更新并安装 feeds
    ./scripts/feeds update -a 2>&1 | tail -3
    ./scripts/feeds install -a 2>&1 | tail -3
}

# ============================================================================
# 🔧 模块 2: 内核同步 (根据官方版本调整)
# ============================================================================
sync_kernel() {
    [ "$ENABLE_KERNEL_SYNC" != "true" ] && return 0
    log_info "🔧 同步内核 (官方版建议保留默认)..."
    
    # 官方OpenWrt建议不修改默认内核版本
    # 如果确实需要，检查 target/linux/mediatek/Makefile 中的可用版本
    # sed -i 's/KERNEL_PATCHVER[:=].*/KERNEL_PATCHVER:=6.6/' target/linux/mediatek/Makefile 2>/dev/null || true
    log_warn "官方源码建议使用默认内核，跳过强制同步"
}

# ============================================================================
# 🔧 模块 3: 基础配置适配
# ============================================================================
apply_base() {
    log_info "🔧 应用基础配置适配..."
    
    # 官方OpenWrt没有LEDE的默认设置脚本，跳过相关修改
    # 只修改主机名相关设置
    if [ -f "package/base-files/files/bin/config_generate" ]; then
        sed -i "s/option hostname 'OpenWrt'/option hostname '${DEVICE_NAME}'/g" \
            package/base-files/files/bin/config_generate 2>/dev/null || true
    fi
    
    # 移除密码相关设置（官方版无预设密码）
    log_info "✓ 基础配置适配完成"
}

# ============================================================================
# 📶 模块 4: WiFi 配置 (通用)
# ============================================================================
setup_wifi() {
    log_info "📶 生成 WiFi 配置 (前缀: $WIFI_PREFIX)..."
    local script="package/kernel/mac80211/files/lib/wifi/mac80211.sh"
    mkdir -p "$(dirname "$script")"
    
    # 使用简化模板
    cat > "$script" << EOF
#!/bin/sh
append DRIVERS "mac80211"
WIFI_PREFIX="$WIFI_PREFIX"
WIFI_KEY="$WIFI_PASSWORD"

detect_mac80211() {
    [ -f "/etc/.wifi_customized" ] && return 0
    [ ! -s /etc/config/wireless ] && rm -f /etc/.wifi_customized
    local devidx=0
    config_load wireless
    while :; do config_get type "radio\$devidx" type; [ -n "\$type" ] || break; devidx=\$((devidx + 1)); done
    for _dev in /sys/class/ieee80211/*; do
        [ -e "\$_dev" ] || continue
        dev="\${_dev##*/}"
        local mac=\$(cat /sys/class/ieee80211/\${dev}/macaddress 2>/dev/null | tr -d ':')
        local suffix="\${mac: -4}"; [ -z "\$suffix" ] && suffix="0000"
        local band="2G"; iwinfo nl80211 info "\$dev" 2>/dev/null | grep -q "5GHz" && band="5G"
        local ssid="\${WIFI_PREFIX}\${suffix}_\${band}"
        uci -q batch << UCIEOF
set wireless.radio\${devidx}=wifi-device
set wireless.radio\${devidx}.type=mac80211
set wireless.radio\${devidx}.channel=auto
set wireless.radio\${devidx}.band=\${band%G}g
set wireless.radio\${devidx}.htmode=HE80
set wireless.radio\${devidx}.disabled=0
set wireless.radio\${devidx}.country=CN
set wireless.default_radio\${devidx}=wifi-iface
set wireless.default_radio\${devidx}.device=radio\${devidx}
set wireless.default_radio\${devidx}.network=lan
set wireless.default_radio\${devidx}.mode=ap
set wireless.default_radio\${devidx}.ssid=\$ssid
set wireless.default_radio\${devidx}.encryption=psk2
set wireless.default_radio\${devidx}.key=\$WIFI_KEY
UCIEOF
        devidx=\$((devidx + 1))
    done
    touch /etc/.wifi_customized
}
[ "\$1" = "detect" ] && detect_mac80211
EOF
    chmod +x "$script"
    log_info "✓ WiFi 配置完成"
}

# ============================================================================
# 🔤 模块 5: 汉化
# ============================================================================
apply_translate() {
    [ "$ENABLE_TRANSLATE" != "true" ] && { log_info "⏭️ 跳过汉化"; return 0; }
    log_info "🔤 应用汉化..."
    
    # 使用辅助脚本或内联
    if declare -f translate_file &>/dev/null; then
        find package feeds -type f \( -name "*.lua" -o -name "*.po" \) 2>/dev/null | while read -r f; do
            translate_file "$f" 2>/dev/null || true
        done
    else
        # 内联简化映射
        for old in "AdGuard Home" "PassWall" "软件包"; do
            new="AdGuard"; [ "$old" = "PassWall" ] && new="科学上网"; [ "$old" = "软件包" ] && new="插件管理"
            find package feeds -type f -name "*.lua" -exec sed -i "s|\"$old\"|\"$new\"|g" {} \; 2>/dev/null || true
        done
    fi
    log_info "✓ 汉化完成"
}

# ============================================================================
# ⚔️ 模块 6: 冲突预检
# ============================================================================
resolve_conflicts() {
    log_info "⚔️ 冲突预检..."
    [ ! -f ".config" ] && return 0
    
    # 使用辅助脚本或内联
    if declare -f resolve_conflicts &>/dev/null; then
        resolve_conflicts ".config"
    else
        # 简化：只处理常见冲突
        if grep -q "vsftpd-alt" .config 2>/dev/null; then
            sed -i 's/^CONFIG_PACKAGE_vsftpd=[ym]/# &/' .config 2>/dev/null || true
            sed -i 's/^CONFIG_PACKAGE_luci-app-vsftpd=[ym]/# &/' .config 2>/dev/null || true
        fi
        if grep -q "dnsmasq-full" .config 2>/dev/null && grep -q "dnsmasq" .config 2>/dev/null; then
            sed -i 's/^CONFIG_PACKAGE_dnsmasq=[ym]/# &/' .config 2>/dev/null || true
        fi
    fi
    make defconfig >/dev/null 2>&1
    log_info "✓ 冲突预检完成"
}

# ============================================================================
# 🚀 主流程
# ============================================================================
main() {
    log_info "🔧 开始配置官方OpenWrt (设备: $DEVICE)"
    
    load_helpers
    configure_feeds
    sync_kernel
    apply_base
    setup_wifi
    apply_translate
    resolve_conflicts
    
    log_info "✅ 官方OpenWrt配置完成"
}

main "$@"
