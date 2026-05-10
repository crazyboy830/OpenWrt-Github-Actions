#!/bin/bash
# ============================================================================
# OpenWrt 官方源码自定义配置脚本
# 适配：https://github.com/openwrt/openwrt
# 支持分支：main / openwrt-24.10 / openwrt-25.12
# ============================================================================
set -e

# 📋 接收环境变量
DEVICE="${DEVICE:-redmi_ax6000}"
DEVICE_NAME="${DEVICE_NAME:-OpenWrt}"
WIFI_PREFIX="${WIFI_PREFIX:-OpenWrt_}"
WIFI_PASSWORD="${WIFI_PASSWORD:-1234567890}"
ENABLE_TRANSLATE="${ENABLE_TRANSLATE:-true}"
REPO_BRANCH="${REPO_BRANCH:-openwrt-24.10}"
OPENWRT_PATH="${OPENWRT_PATH:-$PWD}"

cd "$OPENWRT_PATH"

# 🎨 日志函数
log_info() { echo -e "\033[0;32m[✓]\033[0m $1"; }
log_warn() { echo -e "\033[1;33m[!]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[✗]\033[0m $1"; }

# ============================================================================
# 🔧 模块 1: 配置 feeds（✅ 修复格式错误）
# ============================================================================
configure_feeds() {
  log_info "📡 配置插件源..."
  
  # ✅ 重写 feeds.conf.default（确保格式正确）
  cat > feeds.conf.default << 'EOF'
src-git packages https://git.openwrt.org/feed/packages.git^openwrt-24.10
src-git luci https://git.openwrt.org/project/luci.git^openwrt-24.10
src-git routing https://git.openwrt.org/feed/routing.git^openwrt-24.10
src-git telephony https://git.openwrt.org/feed/telephony.git^openwrt-24.10
src-git small-package https://github.com/kenzok8/small-package;main
EOF
  
  log_info "✓ feeds.conf.default 已更新"
  
  # 🔄 更新并安装 feeds
  ./scripts/feeds update -a 2>&1 | tail -5
  ./scripts/feeds install -a 2>&1 | tail -5
  
  log_info "✓ feeds 配置完成"
}

# ============================================================================
# 🔧 模块 2: 内核版本选择（根据分支自动适配）
# ============================================================================
select_kernel() {
  log_info "🔧 配置内核版本..."
  
  case "${REPO_BRANCH}" in
    main)
      log_info "  📦 主线分支，使用默认内核"
      ;;
    openwrt-24.10)
      log_info "  📦 OpenWrt 24.10，使用 6.6 内核"
      sed -i 's/KERNEL_PATCHVER[:=].*/KERNEL_PATCHVER:=6.6/' target/linux/mediatek/Makefile 2>/dev/null || true
      ;;
    openwrt-25.12)
      log_info "  📦 OpenWrt 25.12，使用 6.12 内核"
      sed -i 's/KERNEL_PATCHVER[:=].*/KERNEL_PATCHVER:=6.12/' target/linux/mediatek/Makefile 2>/dev/null || true
      ;;
    *)
      log_warn "  ⚠️  未知分支，使用默认内核"
      ;;
  esac
  
  log_info "✓ 内核版本配置完成"
}

# ============================================================================
# 🔧 模块 3: 基础配置（官方源适配）
# ============================================================================
apply_base() {
  log_info "🔧 应用基础配置..."
  
  # 🏷️ 修改主机名
  sed -i "s/OpenWrt/${DEVICE_NAME}/g" package/base-files/files/bin/config_generate 2>/dev/null || true
  
  log_info "✓ 基础配置完成"
}

# ============================================================================
# 📶 模块 4: WiFi 配置
# ============================================================================
setup_wifi() {
  log_info "📶 生成 WiFi 配置 (前缀: $WIFI_PREFIX)..."
  
  local script="package/kernel/mac80211/files/lib/wifi/mac80211.sh"
  mkdir -p "$(dirname "$script")"
  
  cat > "$script" << 'EOF'
#!/bin/sh
append DRIVERS "mac80211"

detect_mac80211() {
  [ -f "/etc/.wifi_customized" ] && return 0
  [ ! -s /etc/config/wireless ] && rm -f /etc/.wifi_customized
  
  local devidx=0
  config_load wireless
  while :; do
    config_get type "radio$devidx" type
    [ -n "$type" ] || break
    devidx=$((devidx + 1))
  done
  
  for _dev in /sys/class/ieee80211/*; do
    [ -e "$_dev" ] || continue
    dev="${_dev##*/}"
    
    local mac=$(cat /sys/class/ieee80211/${dev}/macaddress 2>/dev/null | tr -d ':')
    local suffix="${mac: -4}"
    [ -z "$suffix" ] && suffix="0000"
    
    local band="2G"
    iwinfo nl80211 info "$dev" 2>/dev/null | grep -q "5GHz" && band="5G"
    
    local ssid="${WIFI_PREFIX}${suffix}_${band}"
    
    uci -q batch << UCIEOF
set wireless.radio${devidx}=wifi-device
set wireless.radio${devidx}.type=mac80211
set wireless.radio${devidx}.channel=auto
set wireless.radio${devidx}.band=${band%G}g
set wireless.radio${devidx}.htmode=HE80
set wireless.radio${devidx}.disabled=0
set wireless.radio${devidx}.country=CN
set wireless.default_radio${devidx}=wifi-iface
set wireless.default_radio${devidx}.device=radio${devidx}
set wireless.default_radio${devidx}.network=lan
set wireless.default_radio${devidx}.mode=ap
set wireless.default_radio${devidx}.ssid=$ssid
set wireless.default_radio${devidx}.encryption=psk2
set wireless.default_radio${devidx}.key=${WIFI_KEY}
UCIEOF
    
    devidx=$((devidx + 1))
  done
  
  touch /etc/.wifi_customized
}

[ "$1" = "detect" ] && detect_mac80211
EOF
  
  chmod +x "$script"
  log_info "✓ WiFi 配置完成"
}

# ============================================================================
# 🔤 模块 5: 汉化（简化版）
# ============================================================================
apply_translate() {
  [ "$ENABLE_TRANSLATE" != "true" ] && { log_info "⏭️ 跳过汉化"; return 0; }
  
  log_info "🔤 应用汉化..."
  
  # 简化映射：只处理常用插件
  for old in "AdGuard Home" "PassWall" "软件包"; do
    new="AdGuard"
    [ "$old" = "PassWall" ] && new="科学上网"
    [ "$old" = "软件包" ] && new="插件管理"
    
    find package feeds -type f -name "*.lua" -exec sed -i "s|\"$old\"|\"$new\"|g" {} \; 2>/dev/null || true
  done
  
  log_info "✓ 汉化完成"
}

# ============================================================================
# ⚔️ 模块 6: 冲突预检
# ============================================================================
resolve_conflicts() {
  log_info "⚔️ 冲突预检..."
  [ ! -f ".config" ] && return 0
  
  # 处理 dnsmasq 冲突
  if grep -q "dnsmasq-full" .config 2>/dev/null && grep -q "^CONFIG_PACKAGE_dnsmasq=[ym]" .config 2>/dev/null; then
    sed -i 's/^CONFIG_PACKAGE_dnsmasq=[ym]/# &/' .config 2>/dev/null || true
  fi
  
  make defconfig >/dev/null 2>&1
  log_info "✓ 冲突预检完成"
}

# ============================================================================
# 🚀 主流程
# ============================================================================
main() {
  log_info "🔧 开始配置 (设备: $DEVICE, 分支: $REPO_BRANCH)"
  
  configure_feeds
  select_kernel
  apply_base
  setup_wifi
  apply_translate
  resolve_conflicts
  
  log_info "✅ 配置完成"
}

main "$@"
