#!/bin/bash
# diy/scripts/translate-map.sh - OpenWrt 插件汉化映射表
# 用法: source translate-map.sh && translate_file <文件路径>

# 📋 声明关联数组（需 Bash 4.0+）
declare -gA TRANSLATE_MAP=(
    # 🔤 A
    ["AdGuard Home"]="AdGuard"
    ["Alist"]="网盘管理"
    ["Alist 文件列表"]="网盘列表"
    ["AirPlay 2 音频接收器"]="AirPlay 接收"
    ["aMule 设置"]="eMule 下载"
    ["Argon 主题设置"]="主题设置"
    
    # 🔤 B
    ["备份与更新"]="备份/更新"
    ["备份与升级"]="备份/升级"
    ["带宽监控"]="带宽监视"
    
    # 🔤 D
    ["DDNSTO 远程控制"]="远程控制"
    
    # 🔤 F
    ["FileBrowser"]="文件管理"
    ["FTP 服务器"]="FTP 服务"
    
    # 🔤 I
    ["iKoolProxy 滤广告"]="广告过滤"
    
    # 🔤 K
    ["KMS 服务器"]="KMS 激活"
    
    # 🔤 L
    ["Lucky 大吉"]="大吉工具"
    ["登录页面"]="登录界面"
    
    # 🔤 M
    ["挂载点"]="挂载设置"
    ["挂载 SMB 网络共享"]="SMB 共享"
    ["MWAN3 分流助手"]="负载均衡"
    
    # 🔤 O
    ["Online User"]="在线用户"
    ["OpenVPN 服务器"]="OpenVPN"
    
    # 🔤 P
    ["PassWall"]="科学上网"
    ["PPTP VPN 服务器"]="PPTP"
    ["进程"]="系统进程"
    
    # 🔤 R
    ["实时流量监测"]="实时流量"
    
    # 🔤 S
    ["SFTP 服务器"]="SFTP 服务"
    ["ShadowSocksR Plus+"]="SSR Plus+"
    ["软件包"]="插件管理"
    ["启动项"]="启动管理"
    
    # 🔤 T
    ["Turbo ACC 网络加速设置"]="网络加速"
    ["Turbo ACC 网络加速"]="网络加速"
    ["TTYD 终端"]="TTYD 终端"
    
    # 🔤 U
    ["udpxy"]="电视组播"
    ["UPnP IGD 和 PCP"]="映射管理"
    ["USB 打印服务器"]="打印服务"
    
    # 🔤 W
    ["Web 管理"]="网页管理"
    ["WireGuard 隧道"]="WireGuard"
    
    # 🔤 X
    ["吸附广告大师 Plus+"]="广告屏蔽"
    ["吸附屏蔽大师 Plus+"]="广告屏蔽"
    
    # 🔤 Y
    ["UU 游戏加速器"]="游戏加速"
    
    # 🔤 其他
    ["管理权"]="权限管理"
    ["流量监控"]="流量统计"
    ["磁盘管理"]="存储管理"
    ["重启"]="重启系统"
    ["网络存储"]="NAS"
    ["上网时间控制"]="上网管理"
    ["IPSec VPN 服务器"]="IPSec"
    ["SoftEther VPN 服务器"]="SoftEther"
)

# 🔧 辅助函数：批量替换文件中的插件名
translate_file() {
    local file="$1"
    local count=0
    
    for old_name in "${!TRANSLATE_MAP[@]}"; do
        local new_name="${TRANSLATE_MAP[$old_name]}"
        # 🔍 精准替换双引号包裹的名称（避免误替换代码变量）
        if grep -q "\"$old_name\"" "$file" 2>/dev/null; then
            sed -i "s|\"$old_name\"|\"$new_name\"|g" "$file"
            ((count++)) || true
        fi
    done
    
    [ $count -gt 0 ] && echo "✓ $file: 替换 $count 项" || true
    return 0
}

# 🔧 辅助函数：导出为 JSON 格式（供其他脚本调用）
export_translate_json() {
    echo "{"
    local first=true
    for key in "${!TRANSLATE_MAP[@]}"; do
        $first || echo ","
        first=false
        printf '  "%s": "%s"' "$key" "${TRANSLATE_MAP[$key]}"
    done
    echo -e "\n}"
}

# 🎯 主函数：当直接执行时显示帮助
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --json) export_translate_json ;;
        --help|*) 
            echo "用法: source translate-map.sh"
            echo "      translate_file <文件路径>  # 替换指定文件中的插件名"
            echo "      ./translate-map.sh --json  # 导出 JSON 格式"
            ;;
    esac
fi
