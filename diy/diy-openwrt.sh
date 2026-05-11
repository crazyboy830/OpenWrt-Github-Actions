#!/bin/bash
# diy/scripts/conflict-resolver.sh - OpenWrt 包冲突自动解决器
# 用法: ./conflict-resolver.sh .config  或  source conflict-resolver.sh && run_conflict_resolver

set -euo pipefail

CONFIG_FILE="${1:-.config}"
LOG_PREFIX="[CONFLICT]"

# 🎯 核心冲突对定义: "冲突包:替代包:说明"
declare -A CONFLICT_PAIRS=(
    # 🌐 DNS 服务
    ["dnsmasq"]="dnsmasq-full:DNS 服务 (dnsmasq-full 功能更全)"
    
    # 🔥 防火墙
    ["luci-app-firewall"]="luci-app-nftables:防火墙界面 (nftables 为新架构)"
    ["iptables"]="iptables-nft:防火墙规则 (nft 后端)"
    
    # 🔐 SSL 库
    ["libustream-mbedtls"]="libustream-openssl:SSL 流库 (openssl 兼容性更好)"
    ["libustream-openssl"]="libustream-mbedtls:SSL 流库 (mbedtls 体积更小)"
    
    # 📦 NAT 助手
    ["kmod-ipt-nathelper"]="kmod-nf-nathelper:NAT 助手 (旧版→新版)"
    ["kmod-ipt-nathelper-extra"]="kmod-nf-nathelper-extra:NAT 助手扩展"
    
    # 🔄 进程管理
    ["procd"]="procd-ujail:进程守护 (ujail 增强安全)"
    
    # 🗄️ FTP 服务 (✅ 重点修复)
    ["vsftpd"]="vsftpd-alt:FTP 服务器 (alt 版本支持更多特性)"
    ["luci-app-vsftpd"]=":LuCI 界面 (与 vsftpd-alt 不兼容，需禁用)"
)

# 🔍 检查配置项是否启用
is_enabled() {
    local pkg="$1"
    grep -qE "^CONFIG_PACKAGE_${pkg}=[ym]" "$CONFIG_FILE" 2>/dev/null
}

# 🔧 禁用配置项
disable_pkg() {
    local pkg="$1"
    sed -i "s/^CONFIG_PACKAGE_${pkg}=[ym]/# CONFIG_PACKAGE_${pkg} is not set/" "$CONFIG_FILE"
    echo "$LOG_PREFIX 禁用: $pkg"
}

# 🎯 主解决函数 (已重命名以避免与 diy-openwrt.sh 冲突)
run_conflict_resolver() {
    local resolved=0
    echo "$LOG_PREFIX 开始冲突检测: $CONFIG_FILE"
    
    # 🔍 遍历冲突对
    for conflict_pkg in "${!CONFLICT_PAIRS[@]}"; do
        IFS=':' read -r alt_pkg description <<< "${CONFLICT_PAIRS[$conflict_pkg]}"
        
        # 📋 检查是否同时启用
        if is_enabled "$conflict_pkg" && [ -n "$alt_pkg" ] && is_enabled "$alt_pkg"; then
            echo "$LOG_PREFIX ⚠️  冲突: $conflict_pkg ↔ $alt_pkg ($description)"
            
            # 🎯 决策逻辑：优先保留"替代包"
            if [[ "$conflict_pkg" == luci-app-* ]] || [[ "$conflict_pkg" == "vsftpd" ]]; then
                disable_pkg "$conflict_pkg"
                # 🔗 同时禁用关联的 LuCI/汉化包
                if [[ "$conflict_pkg" != luci-app-* ]]; then
                    disable_pkg "luci-app-${conflict_pkg}" 2>/dev/null || true
                    disable_pkg "luci-i18n-${conflict_pkg}-zh-cn" 2>/dev/null || true
                fi
                ((resolved++)) || true
            fi
        fi
    done
    
    # 🎯 特殊处理: vsftpd 冲突链（必须同时禁用 LuCI）
    if is_enabled "vsftpd-alt"; then
        echo "$LOG_PREFIX 🔧 检测 vsftpd-alt，清理冲突链..."
        disable_pkg "vsftpd" 2>/dev/null || true
        disable_pkg "luci-app-vsftpd" 2>/dev/null || true
        disable_pkg "luci-i18n-vsftpd-zh-cn" 2>/dev/null || true
        ((resolved++)) || true
    fi
    
    # 📊 输出结果
    if [ "$resolved" -gt 0 ]; then
        echo "$LOG_PREFIX ✅ 已解决 $resolved 项冲突"
        echo "$LOG_PREFIX 🔄 建议执行: make defconfig 重载配置"
        return 0
    else
        echo "$LOG_PREFIX ✅ 未发现已知冲突"
        return 0
    fi
}

# 🧹 清理打包缓存（解决 opkg 安装冲突）
clean_package_cache() {
    echo "$LOG_PREFIX 🧹 清理包缓存..."
    
    # 🔍 获取目标架构
    local arch=$(grep '^CONFIG_TARGET_ARCH_PACKAGES=' "$CONFIG_FILE" 2>/dev/null | cut -d'"' -f2)
    
    if [ -n "$arch" ]; then
        rm -rf "staging_dir/target-${arch}/root-"* 2>/dev/null || true
        echo "$LOG_PREFIX ✓ 清理: staging_dir/target-${arch}/root-*"
    else
        rm -rf staging_dir/target-*/root-* 2>/dev/null || true
        echo "$LOG_PREFIX ⚠️  未获取架构，使用通配符清理"
    fi
    
    # 🗑️ 清理临时索引
    rm -rf tmp/.packageinfo tmp/.targetinfo tmp/.packageinfo-* 2>/dev/null || true
    echo "$LOG_PREFIX ✓ 清理: tmp/.packageinfo*"
}

# 🎯 当直接执行时运行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "错误: 配置文件不存在: $CONFIG_FILE"
        echo "用法: $0 <.config 文件路径>"
        exit 1
    fi
    run_conflict_resolver
    clean_package_cache
fi
