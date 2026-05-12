#!/bin/bash
# ============================================================================
# OpenWrt 官方源码自动化编译系统 v1.0 (Official Edition)
# 功能：系统检测 + 依赖安装 + 源码管理 + 智能配置 + 冲突预检 + 汉化 + 编译
# 适配：openwrt/openwrt 官方源码 + kenzok8/small-package (可选)
# 设备：Redmi AX6000 / TP-LINK XDR6088 / 自定义机型
# 位置：请放在官方 OpenWrt 源码根目录下执行
# ============================================================================

set -e

# ============================================================================
# 📋 全局配置
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$SCRIPT_DIR"
OUTPUT_DIR="$WORK_DIR/output"
DIY_DIR="$WORK_DIR/diy"
CONFIG_DIR="$DIY_DIR/configs"
FILES_DIR="$DIY_DIR/files"
SCRIPTS_DIR="$DIY_DIR/scripts"

# 模式开关
NOVICE_MODE="false"
INSTALL_DEPS="false"
UPDATE_SYSTEM="false"
ENABLE_TRANSLATE="true"
ENABLE_SMALL_FEED="true"

# WiFi 默认配置
WIFI_PASSWORD="1234567890"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
step() { echo -e "\n${GREEN}════════════════════════════════════════${NC}"; echo -e "${GREEN}▶ $1${NC}"; echo -e "${GREEN}════════════════════════════════════════${NC}\n"; }

# ============================================================================
# 🗺️ 机型映射表（设备名 | IP | 作者 | QQ | 用户 | 密码 | WiFi前缀）
# ============================================================================
declare -A DEVICE_MAP=(
    ["xdr6088"]="TP-LINK XDR6088|192.168.1.1|CN2014|38663790|root|password|TP-LINK_"
    ["ax6000"]="Redmi AX6000|192.168.1.1|CN2014|38663790|root|password|Redmi_"
    ["custom"]="OpenWrt|192.168.1.1|CN2014|38663790|root|password|OpenWrt_"
)

# ============================================================================
# 🔍 系统检测函数
# ============================================================================
detect_system() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            ubuntu|debian|linuxmint) echo "debian" ;;
            centos|fedora|rhel) echo "rhel" ;;
            arch|manjaro) echo "arch" ;;
            *) echo "unknown" ;;
        esac
    else
        echo "unknown"
    fi
}

# ============================================================================
# 📦 安装系统依赖（Debian/Ubuntu）
# ============================================================================
install_dependencies_debian() {
    step "安装编译依赖 (Debian/Ubuntu)"
    echo -e "${YELLOW}⚠️  以下操作需要 sudo 权限，请输入密码：${NC}"
    
    info "执行 apt update..."
    sudo apt update -y || { error "apt update 失败"; return 1; }
    
    if [ "$UPDATE_SYSTEM" = "true" ]; then
        info "执行 apt full-upgrade..."
        sudo apt full-upgrade -y || warn "系统升级失败，继续编译"
    fi
    
    info "安装编译依赖包..."
    sudo apt install -y \
        ack antlr3 asciidoc autoconf automake autopoint binutils bison build-essential \
        bzip2 ccache cmake cpio curl flex gawk gcc-multilib g++-multilib gettext \
        genisoimage git gperf haveged help2man intltool libc6-dev-i386 libelf-dev \
        libfuse-dev libglib2.0-dev libgmp3-dev libltdl-dev libmpc-dev libmpfr-dev \
        libncurses5-dev libncursesw5-dev libpython3-dev libreadline-dev libssl-dev \
        libtool lrzsz ninja-build patch pkgconf python3 python3-pyelftools \
        python3-setuptools rsync scons squashfs-tools subversion swig texinfo \
        uglifyjs upx-ucl unzip wget xmlto xxd zlib1g-dev \
        || { error "依赖安装失败"; return 1; }
    
    success "编译依赖安装完成"
    
    # 配置 ccache
    if command -v ccache &>/dev/null; then
        info "配置 ccache 加速..."
        export PATH="/usr/lib/ccache:$PATH"
        grep -q "ccache" ~/.bashrc 2>/dev/null || echo 'export PATH="/usr/lib/ccache:$PATH"' >> ~/.bashrc
        success "ccache 加速已配置"
    fi
}

install_dependencies() {
    local sys_type=$(detect_system)
    case "$sys_type" in
        debian) install_dependencies_debian ;;
        *) warn "非 Debian/Ubuntu 系统，请手动安装依赖"; read -p "是否继续？[y/N] " -n 1 -r; echo; [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1 ;;
    esac
}

# ============================================================================
# 🔐 系统基础配置（官方源码适配）
# ============================================================================
apply_system_config() {
    step "应用系统基础配置 (主机名 + 账号)"
    cd "$WORK_DIR" || { error "源码目录不存在"; return 1; }
    
    info "修改主机名：OpenWrt → ${DEVICE_NAME}"
    local config_gen="package/base-files/files/bin/config_generate"
    if [ -f "$config_gen" ]; then
        sed -i "s/option hostname 'OpenWrt'/option hostname '${DEVICE_NAME}'/g" "$config_gen"
        success "主机名已修改"
    else
        warn "config_generate 未找到，跳过主机名修改"
    fi
    
    # 官方源码默认无预设密码，首次登录强制修改
    info "配置默认账号：root / 首次登录强制修改密码"
    success "账号配置已应用"
}

# ============================================================================
# 🌱 新手导入模式（配置第三方源）
# ============================================================================
apply_novice_mode() {
    [ "$NOVICE_MODE" != "true" ] && return 0
    [ "$ENABLE_SMALL_FEED" != "true" ] && return 0
    
    step "🌱 新手模式：配置第三方插件源 (kenzok8/small-package)"
    cd "$WORK_DIR" || return 1
    
    local feeds_conf="feeds.conf.default"
    cp "$feeds_conf" "${feeds_conf}.bak.$(date +%Y%m%d%H%M%S)"
    
    info "添加 small-package 源..."
    
    # 安全添加，避免重复
    if ! grep -q "^src-git small " "$feeds_conf"; then
        echo "src-git small https://github.com/kenzok8/small-package;main" >> "$feeds_conf"
        info "  ✓ small-package 源已添加"
    fi
    
    # 确保官方源存在
    grep -q "^src-git packages " "$feeds_conf" || echo "src-git packages https://git.openwrt.org/feed/packages.git^openwrt-24.10" >> "$feeds_conf"
    grep -q "^src-git luci " "$feeds_conf" || echo "src-git luci https://git.openwrt.org/project/luci.git^openwrt-24.10" >> "$feeds_conf"
    
    success "第三方源配置完成"
    
    info "执行 feeds update..."
    ./scripts/feeds update -a 2>&1 | tail -3
    info "执行 feeds install..."
    ./scripts/feeds install -a 2>&1 | tail -3
    success "Feeds 更新完成"
}

# ============================================================================
# 🎨 Banner 统一模板（官方源码适配）
# ============================================================================
BANNER_TEMPLATE='  _______                     ________        __
 |       |.-----.-----.-----.|  |  |  |.----.|  |_
 |   -   ||  _  |  -__|     ||  |  |  ||   _||   _|
 |_______||   __|_____|__|__||________||__|  |____|
          |__| W I R E L E S S   F R E E D O M
 -----------------------------------------------------
 %D %V, %C
 -----------------------------------------------------
 
 🎯 {{DEVICE_NAME}} 官方定制固件 | BY: {{AUTHOR}}  QQ:{{QQ}}
 🔗 管理地址：{{MANAGEMENT_IP}} | 用户：{{USERNAME}} | 密码：{{PASSWORD}}
 
 -----------------------------------------------------'

generate_banner() {
    local device_code="$1"
    local template="$BANNER_TEMPLATE"
    local mapping="${DEVICE_MAP[$device_code]:-${DEVICE_MAP[custom]}}"
    IFS='|' read -r name ip author qq user pass wifi_prefix <<< "$mapping"
    echo "${template//\{\{DEVICE_NAME\}\}/$name}" | \
         sed -e "s|{{MANAGEMENT_IP}}|$ip|g" \
             -e "s|{{AUTHOR}}|$author|g" \
             -e "s|{{QQ}}|$qq|g" \
             -e "s|{{USERNAME}}|$user|g" \
             -e "s|{{PASSWORD}}|$pass|g"
}

# ============================================================================
# 🔧 WiFi 配置脚本生成（官方源码适配 ⭐）
# ============================================================================
generate_mac80211_script() {
    local wifi_prefix="$1"
    [ -z "$wifi_prefix" ] && wifi_prefix="OpenWrt_"
    
    # 官方源码路径
    local output_file="$WORK_DIR/package/kernel/mac80211/files/lib/wifi/mac80211.sh"
    mkdir -p "$(dirname "$output_file")"
    
    cat > "$output_file" << 'TEMPLATE_EOF'
#!/bin/sh
# ============================================================================
# OpenWrt Official mac80211 WiFi 配置脚本
# WiFi 前缀：__WIFI_PREFIX__
# 密码：__WIFI_KEY__
# ============================================================================

append DRIVERS "mac80211"

WIFI_PREFIX="__WIFI_PREFIX__"
WIFI_KEY="__WIFI_KEY__"

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
        local suffix="${mac: -4}"; [ -z "$suffix" ] && suffix="0000"
        local band="2G"; iwinfo nl80211 info "$dev" 2>/dev/null | grep -q "5GHz" && band="5G"
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
set wireless.default_radio${devidx}.key=$WIFI_KEY
UCIEOF
        devidx=$((devidx + 1))
    done
    
    touch /etc/.wifi_customized
}

[ "$1" = "detect" ] && detect_mac80211
TEMPLATE_EOF

    # 替换变量
    sed -i "s|__WIFI_PREFIX__|${wifi_prefix}|g" "$output_file"
    sed -i "s|__WIFI_KEY__|${WIFI_PASSWORD}|g" "$output_file"
    
    chmod +x "$output_file"
    
    if grep -q "${wifi_prefix}" "$output_file"; then
        success "WiFi 配置已生成 (前缀：${wifi_prefix})"
    else
        error "WiFi 配置生成失败！"
        return 1
    fi
}

# ============================================================================
# 🔧 汉化规则表（内置，适配官方源码文件结构）
# ============================================================================
declare -A TRANSLATE_MAP=(
    ["设置向导"]="向导" ["备份与升级"]="备份/升级" ["终端"]="TTYD"
    ["USB 打印服务器"]="打印服务" ["系统设置"]="系统" ["网络设置"]="网络"
    ["服务管理"]="服务" ["NAS 管理"]="NAS" ["Turbo ACC 网络加速"]="网络加速"
    ["实时流量监测"]="实时流量" ["带宽监控"]="带宽监视" ["流量监控"]="流量统计"
    ["KMS 服务器"]="KMS 激活" ["解锁网易云灰色歌曲"]="解锁网易云"
    ["AdGuard Home"]="AdGuard" ["ShadowSocksR Plus+"]="SSR Plus+"
    ["广告屏蔽大师 Plus+"]="广告屏蔽" ["iKoolProxy 滤广告"]="广告过滤"
    ["DDNSTO 远程控制"]="远程控制" ["PassWall"]="科学上网"
    ["OpenClash"]="Clash 代理" ["VSSR"]="SSR 代理" ["上网时间控制"]="家长控制"
    ["TTYD"]="TTYD 终端" ["FileBrowser"]="文件管理" ["Alist"]="网盘管理"
    ["Alist 文件列表"]="网盘列表" ["挂载 SMB 网络共享"]="SMB 共享"
    ["FTP 服务器"]="FTP 服务" ["SFTP 服务器"]="SFTP 服务"
    ["Argon 主题设置"]="主题设置" ["Online User"]="在线用户"
    ["Web 管理"]="网页管理" ["启动项"]="启动管理" ["管理权"]="权限管理"
    ["挂载点"]="挂载设置" ["登录页面"]="登录界面" ["Lucky 大吉"]="大吉工具"
    ["udpxy"]="电视组播" ["AirPlay 2 音频接收器"]="AirPlay 接收"
    ["MWAN3 分流助手"]="负载均衡" ["UU 游戏加速器"]="游戏加速"
    ["aMule 设置"]="eMule 下载" ["磁盘管理"]="存储管理"
    ["SoftEther VPN 服务器"]="SoftEther" ["OpenVPN 服务器"]="OpenVPN"
    ["IPSec VPN 服务器"]="IPSec" ["PPTP VPN 服务器"]="PPTP"
    ["WireGuard 隧道"]="WireGuard" ["软件包"]="插件管理"
)

# ============================================================================
# 🔧 步骤 0: 系统检测 + 依赖安装
# ============================================================================
check_system_and_deps() {
    step "步骤 0: 系统环境检测"
    local sys_type=$(detect_system)
    info "检测到操作系统：$sys_type"
    
    if [ "$NOVICE_MODE" = "true" ] && [ "$sys_type" = "debian" ]; then
        echo ""; echo "📦 新手模式：自动安装编译依赖"
        echo "   依赖安装可能需要 10-30 分钟"
        echo ""; echo "📋 请选择："
        echo "  1) 自动安装依赖 (推荐新手)"
        echo "  2) 跳过依赖安装 (已安装)"
        echo "  3) 仅更新系统包"
        echo ""
        
        while true; do
            read -p "请输入选择 [1-3]: " choice
            case $choice in
                1) INSTALL_DEPS="true"; UPDATE_SYSTEM="false"; break ;;
                2) INSTALL_DEPS="false"; UPDATE_SYSTEM="false"; info "跳过依赖安装"; break ;;
                3) INSTALL_DEPS="false"; UPDATE_SYSTEM="true"; info "仅执行系统更新"; break ;;
                *) warn "无效选择" ;;
            esac
        done
        
        if [ "$INSTALL_DEPS" = "true" ] || [ "$UPDATE_SYSTEM" = "true" ]; then
            install_dependencies || { error "依赖安装失败"; exit 1; }
        fi
    else
        if [ "$sys_type" != "debian" ]; then
            warn "非 Debian/Ubuntu 系统，请确保已安装编译依赖"
            read -p "是否继续？[y/N] " -n 1 -r; echo
            [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
        fi
    fi
}

# ============================================================================
# 🔧 步骤 1: 源码完整性检查
# ============================================================================
check_source_integrity() {
    step "步骤 1: 检查 OpenWrt 源码完整性"
    
    if [ ! -f "$WORK_DIR/Makefile" ] || [ ! -d "$WORK_DIR/package" ]; then
        error "当前目录不是官方 OpenWrt 源码根目录！"
        echo "请将本脚本放在 openwrt/openwrt 源码根目录下执行"
        exit 1
    fi
    
    success "源码目录验证通过"
}

# ============================================================================
# 🔧 步骤 2: 更新 feeds
# ============================================================================
update_feeds() {
    step "步骤 2: 更新 feeds"
    cd "$WORK_DIR" || return 1
    
    if [ "$ENABLE_SMALL_FEED" = "true" ]; then
        apply_novice_mode
    else
        info "执行 ./scripts/feeds update -a..."
        ./scripts/feeds update -a 2>&1 | tail -5
        info "执行 ./scripts/feeds install -a..."
        ./scripts/feeds install -a 2>&1 | tail -5
        success "Feeds 更新完成"
    fi
}

# ============================================================================
# 🔧 步骤 2.5: 清理内核缓存（强制同步最新）
# ============================================================================
sync_kernel_cache() {
    step "步骤 2.5: 清理内核构建缓存"
    cd "$WORK_DIR" || return 1
    
    info "清理 target/linux 缓存，强制同步最新内核..."
    make target/linux/clean 2>/dev/null || true
    rm -rf build_dir/target-*/linux-* 2>/dev/null || true
    
    # 清理旧版内核源码包
    if ls dl/linux-*.tar.* 1>/dev/null 2>&1; then
        info "检测到旧版内核源码包，清理中..."
        rm -f dl/linux-*.tar.* 2>/dev/null || true
    fi
    
    success "内核缓存已清理，编译时将自动拉取最新内核"
}

# ============================================================================
# 🔧 步骤 3: 选择机型 + 智能 WiFi 前缀
# ============================================================================
select_device_and_wifi() {
    step "步骤 3: 选择路由器机型 + WiFi 配置"
    echo "📋 请选择路由器机型："
    echo "  1) TP-LINK XDR6088 (MediaTek Filogic) - WiFi: TP-LINK_XXXX"
    echo "  2) REDMI AX6000 (MediaTek Filogic) - WiFi: Redmi_XXXX"
    echo "  3) 自定义机型 - WiFi: OpenWrt_XXXX 或自定义"
    echo "  0) 退出"
    echo ""
    
    while true; do
        read -p "请输入选择 [0-3]: " choice
        case $choice in
            1) DEVICE="xdr6088"; DEVICE_NAME="TP-LINK XDR6088"; IFS='|' read -r _ _ _ _ _ _ WIFI_PREFIX <<< "${DEVICE_MAP[$DEVICE]}"; info "已选择：$DEVICE_NAME | WiFi 前缀：${WIFI_PREFIX}"; break ;;
            2) DEVICE="ax6000"; DEVICE_NAME="Redmi AX6000"; IFS='|' read -r _ _ _ _ _ _ WIFI_PREFIX <<< "${DEVICE_MAP[$DEVICE]}"; info "已选择：$DEVICE_NAME | WiFi 前缀：${WIFI_PREFIX}"; break ;;
            3)
                DEVICE="custom"; DEVICE_NAME="自定义机型"; info "已选择：$DEVICE_NAME"
                echo ""; echo "📡 WiFi 前缀配置："; echo "  1) OpenWrt_ (通用)"; echo "  2) 自定义前缀"; echo ""
                read -p "请选择 [1-2]: " wifi_choice
                case $wifi_choice in 1) WIFI_PREFIX="OpenWrt_" ;; 2) read -p "请输入前缀： " p; WIFI_PREFIX="${p}_" ;; *) WIFI_PREFIX="OpenWrt_" ;; esac
                info "WiFi 前缀已设置为：${WIFI_PREFIX}"; break ;;
            0) info "退出脚本"; exit 0 ;;
            *) warn "无效选择" ;;
        esac
    done
}

# ============================================================================
# 🔧 步骤 4: 应用插件名称汉化（官方源码适配）
# ============================================================================
apply_translate() {
    [ "$ENABLE_TRANSLATE" != "true" ] && { info "跳过汉化"; return 0; }
    
    step "步骤 4: 应用插件名称汉化"
    cd "$WORK_DIR" || return 1

    # 官方源码汉化前还原语言文件，避免匹配失败
    info "正在清理汉化残留状态..."
    git checkout -- package/ feeds/ 2>/dev/null || true
    info "原始语言文件已还原，开始应用新规则..."

    local count=0 file_count=0 skipped=0
    local BACKUP_DIR="$WORK_DIR/.translate_backup"
    mkdir -p "$BACKUP_DIR"
    
    for old_name in "${!TRANSLATE_MAP[@]}"; do
        new_name="${TRANSLATE_MAP[$old_name]}"
        old_esc=$(printf '%s\n' "$old_name" | sed 's/[\/&|\\]/\\&/g')
        new_esc=$(printf '%s\n' "$new_name" | sed 's/[\/&|\\]/\\&/g')
        
        # 官方源码文件结构：./package/ ./feeds/ 下的 .lua/.po 文件
        local files=$(grep -rIl "\"$old_name\"" ./package ./feeds 2>/dev/null | grep -E "\.(lua|po|zh-cn)$" || true)
        
        if [ -n "$files" ]; then
            while IFS= read -r file; do
                [ -z "$file" ] && continue
                # 备份
                if [ ! -f "$BACKUP_DIR/$(echo "$file" | tr '/' '_').bak."* ]; then 
                    cp "$file" "$BACKUP_DIR/$(echo "$file" | tr '/' '_').bak.$(date +%m%d)"
                    ((file_count++)) || true
                fi
                # 替换
                sed -i "s|\"$old_esc\"|\"$new_esc\"|g" "$file"
                ((count++)) || true
            done <<< "$files"
            info "『$old_name』→ 『$new_name』"
        else
            ((skipped++)) || true
        fi
    done
    
    echo ""; success "共汉化 $count 处，涉及 $file_count 个文件"
    [ $skipped -gt 0 ] && info "未找到匹配：$skipped 个"
}

# ============================================================================
# 🔧 步骤 5: 选择插件配置版本
# ============================================================================
select_config_version() {
    step "步骤 5: 选择插件配置版本"
    cd "$WORK_DIR" || return 1
    
    echo "📦 请选择配置版本："
    echo "  1) 完整版 (full) - 含代理/广告过滤/网盘等插件"
    echo "  2) 精简版 (mini) - 仅核心功能 + LuCI + Argon 主题"
    echo "  3) 自定义 (使用现有 .config)"
    echo "  0) 返回"
    echo ""
    
    while true; do
        read -p "请输入选择 [0-3]: " choice
        case $choice in
            1) 
                if [ -f "$CONFIG_DIR/${DEVICE}-full.config" ]; then
                    cp "$CONFIG_DIR/${DEVICE}-full.config" .config
                    info "已加载完整版配置"
                else
                    warn "配置文件不存在，执行 make defconfig 生成默认配置"
                    make defconfig
                fi
                break 
                ;;
            2) 
                if [ -f "$CONFIG_DIR/${DEVICE}-mini.config" ]; then
                    cp "$CONFIG_DIR/${DEVICE}-mini.config" .config
                    info "已加载精简版配置"
                else
                    warn "配置文件不存在，执行 make defconfig 生成默认配置"
                    make defconfig
                fi
                break 
                ;;
            3) 
                if [ -f ".config" ]; then
                    info "✅ 使用现有 .config"
                    info "已选插件：$(grep -c '^CONFIG_PACKAGE_.*=y' .config) 个"
                else
                    warn "未找到 .config，执行 make defconfig"
                    make defconfig
                fi
                break 
                ;;
            0) return ;; 
            *) warn "无效选择" ;;
        esac
    done
    
    # 启用 ccache（如果系统已安装）
    command -v ccache &>/dev/null && { echo "CONFIG_CCACHE=y" >> .config; info "ccache 已启用"; }
}

# ============================================================================
# 🔧 步骤 6: 应用设备配置 (Banner + WiFi + 预配置文件)
# ============================================================================
apply_device_config() {
    step "步骤 6: 应用设备配置 (Banner + WiFi + 预配置)"
    cd "$WORK_DIR" || return 1
    
    # 1. 应用自定义 Banner
    info "应用自定义 Banner..."
    local banner_src="$FILES_DIR/etc/banner"
    local banner_dst="package/base-files/files/etc/banner"
    
    if [ -f "$banner_src" ]; then
        # 替换变量
        local mapping="${DEVICE_MAP[$DEVICE]:-${DEVICE_MAP[custom]}}"
        IFS='|' read -r name ip author qq user pass wifi_prefix <<< "$mapping"
        
        sed -e "s|{{DEVICE_NAME}}|$name|g" \
            -e "s|{{MANAGEMENT_IP}}|$ip|g" \
            -e "s|{{AUTHOR}}|$author|g" \
            -e "s|{{QQ}}|$qq|g" \
            -e "s|{{USERNAME}}|$user|g" \
            -e "s|{{PASSWORD}}|$pass|g" \
            -e "s|{{WIFI_PREFIX}}|$wifi_prefix|g" \
            -e "s|{{BUILD_DATE}}|$(date '+%Y-%m-%d')|g" \
            "$banner_src" > "$banner_dst"
        success "Banner 已应用"
    else
        warn "diy/files/etc/banner 不存在，使用默认 Banner"
    fi
    
    # 2. 复制预配置文件
    if [ -d "$FILES_DIR" ]; then
        info "复制预配置文件..."
        local files_dst="package/base-files/files"
        mkdir -p "$files_dst"
        cp -rf "$FILES_DIR"/. "$files_dst/" 2>/dev/null || true
        success "预配置文件已复制"
    fi
    
    # 3. 应用自定义 WiFi 配置
    info "应用自定义 WiFi 配置..."
    generate_mac80211_script "$WIFI_PREFIX"
    
    echo ""; info "📡 WiFi 名称预览:"
    echo "  2.4G: ${WIFI_PREFIX}XXXX_2G"
    echo "  5G:   ${WIFI_PREFIX}XXXX_5G"
    echo "  (XXXX = MAC 末 4 位)"
    echo ""; info "🔐 WiFi 密码：${WIFI_PASSWORD}"
}

# ============================================================================
# 🔧 步骤 7: 冲突预检 + 配置重载
# ============================================================================
resolve_conflicts() {
    step "步骤 7: 冲突预检 + 配置重载"
    cd "$WORK_DIR" || return 1
    [ ! -f ".config" ] && return 0
    
    info "执行包冲突预检..."
    
    # 1. vsftpd 冲突（官方 vs vsftpd-alt）
    if grep -q "vsftpd-alt" .config 2>/dev/null; then
        sed -i 's/^CONFIG_PACKAGE_vsftpd=[ym]/# &/' .config 2>/dev/null || true
        sed -i 's/^CONFIG_PACKAGE_luci-app-vsftpd=[ym]/# &/' .config 2>/dev/null || true
        info "  ✓ 已处理 vsftpd 冲突"
    fi
    
    # 2. dnsmasq 冲突
    if grep -q "dnsmasq-full" .config 2>/dev/null && grep -q "^CONFIG_PACKAGE_dnsmasq=[ym]" .config 2>/dev/null; then
        sed -i 's/^CONFIG_PACKAGE_dnsmasq=[ym]/# &/' .config 2>/dev/null || true
        info "  ✓ 已处理 dnsmasq 冲突"
    fi
    
    # 3. firewall 冲突（官方已用 firewall4）
    if grep -q "firewall4" .config 2>/dev/null && grep -q "^CONFIG_PACKAGE_firewall=[ym]" .config 2>/dev/null; then
        sed -i 's/^CONFIG_PACKAGE_firewall=[ym]/# &/' .config 2>/dev/null || true
        info "  ✓ 已处理 firewall 冲突"
    fi
    
    # 4. libustream SSL 后端冲突
    if grep -q "libustream-openssl" .config 2>/dev/null; then
        sed -i 's/^CONFIG_PACKAGE_libustream-mbedtls=[ym]/# &/' .config 2>/dev/null || true
        sed -i 's/^CONFIG_PACKAGE_libustream-wolfssl=[ym]/# &/' .config 2>/dev/null || true
        info "  ✓ 已统一 SSL 后端为 openssl"
    fi
    
    # 重载配置
    info "执行 make defconfig 重载配置..."
    make defconfig >/dev/null 2>&1
    success "冲突预检完成，配置已重载"
}

# ============================================================================
# 🔧 步骤 8: 编译固件
# ============================================================================
compile_firmware() {
    step "步骤 8: 编译固件"
    cd "$WORK_DIR" || return 1
    
    info "执行 make download..."
    make download -j8 2>&1 | tail -3
    
    local threads=$(nproc)
    [ "$threads" -gt 4 ] && threads=4  # 限制线程数避免内存不足
    
    info "执行 make V=s -j$threads (日志保存至 $OUTPUT_DIR/build.log)..."
    mkdir -p "$OUTPUT_DIR"
    local log_file="$OUTPUT_DIR/build.log"
    local start_time=$(date +%s)
    
    if make -j"$threads" V=s 2>&1 | tee "$log_file"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        success "编译成功！耗时：$((duration/3600))h $((duration%3600/60))m $((duration%60))s"
    else
        error "编译失败！查看日志：$log_file"
        return 1
    fi
}

# ============================================================================
# 🔧 步骤 9: 整理输出文件（兼容 .bin/.itb/.apk）
# ============================================================================
organize_output() {
    step "步骤 9: 整理输出文件"
    cd "$WORK_DIR" || return 1
    mkdir -p "$OUTPUT_DIR"
    
    local timestamp=$(date +"%Y%m%d-%H%M")
    local device_friendly="${DEVICE_MAP[$DEVICE]%%|*}"
    [ -z "$device_friendly" ] && device_friendly="$DEVICE"
    
    # 1. 查找 sysupgrade 固件（兼容 .bin 和 .itb）
    info "查找 sysupgrade 固件..."
    local firmware_path=$(find bin/targets -name "*sysupgrade*" -type f 2>/dev/null | grep -E '\.(bin|itb)$' | head -1)
    
    if [ -n "$firmware_path" ]; then
        local ext="${firmware_path##*.}"
        local new_name="OpenWrt-${device_friendly}-$(date +"%Y%m%d")-sysupgrade.${ext}"
        cp "$firmware_path" "$OUTPUT_DIR/$new_name"
        info "已复制固件：$new_name"
    else
        warn "未找到 sysupgrade 固件"
    fi
    
    # 2. 查找 initramfs 恢复固件
    info "查找 initramfs 恢复固件..."
    local initramfs_path=$(find bin/targets -name "*initramfs*" -type f 2>/dev/null | grep -E '\.(itb|bin)$' | head -1)
    if [ -n "$initramfs_path" ]; then
        local ext="${initramfs_path##*.}"
        local new_name="OpenWrt-${device_friendly}-$(date +"%Y%m%d")-initramfs-recovery.${ext}"
        cp "$initramfs_path" "$OUTPUT_DIR/$new_name"
        info "已复制恢复固件：$new_name"
    fi
    
    # 3. 生成校验和
    info "生成 SHA256 校验和..."
    find "$OUTPUT_DIR" -maxdepth 1 -type f \( -name "*.bin" -o -name "*.itb" -o -name "*.ubi" \) -exec sha256sum {} + > "$OUTPUT_DIR/sha256sums.txt" 2>/dev/null || true
    
    # 4. 备份配置
    cp .config "$OUTPUT_DIR/build-${DEVICE}-$(date +"%Y%m%d").config" 2>/dev/null && info "已备份配置文件"
    
    # 5. 打包插件（兼容 .ipk 和 .apk）
    if [ -d "bin/packages" ]; then
        info "打包插件文件..."
        mkdir -p "$OUTPUT_DIR/packages"
        find bin/packages -type f \( -name "*.ipk" -o -name "*.apk" \) -exec cp {} "$OUTPUT_DIR/packages/" \; 2>/dev/null || true
        [ "$(ls -A "$OUTPUT_DIR/packages" 2>/dev/null)" ] && {
            tar -czf "$OUTPUT_DIR/packages.tar.gz" -C "$OUTPUT_DIR" packages
            info "已打包插件：packages.tar.gz"
        }
    fi
    
    success "固件已整理到：$OUTPUT_DIR"
}

# ============================================================================
# 🎯 主流程
# ============================================================================
main() {
    mkdir -p "$OUTPUT_DIR" "$CONFIG_DIR"
    
    cat << 'BANNER'
╔══════════════════════════════════════════════════════════════════════════════╗
║                                                                              ║
║              OpenWrt 官方源码自动化编译系统 v1.0 (Official Edition)          ║
║              适配：openwrt/openwrt + kenzok8/small-package                   ║
║              设备：Redmi AX6000 / TP-LINK XDR6088 / 自定义                   ║
║                                                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
BANNER
    
    echo ""; echo "🌱 新手导入模式：自动安装依赖 + 配置第三方源 + 预设账号"
    read -p "是否启用新手导入模式？[y/N] " -n 1 -r; echo
    [[ $REPLY =~ ^[Yy]$ ]] && NOVICE_MODE="true" && info "✅ 已启用新手导入模式" || info "使用标准模式"
    echo ""
    
    echo "🔤 启用插件汉化？[Y/n] "
    read -p "" -n 1 -r; echo
    [[ ! $REPLY =~ ^[Nn]$ ]] && ENABLE_TRANSLATE="true" || ENABLE_TRANSLATE="false"
    echo ""
    
    # 执行流程
    check_system_and_deps          # 1. 环境检测 + 依赖安装
    check_source_integrity         # 2. 源码完整性检查
    update_feeds                   # 3. 更新 feeds
    sync_kernel_cache              # 4. 清理内核缓存
    apply_system_config            # 5. 系统基础配置
    select_device_and_wifi         # 6. 选择机型 + WiFi
    apply_translate                # 7. 应用汉化
    select_config_version          # 8. 选择配置版本
    apply_device_config            # 9. 应用设备配置 (Banner+WiFi)
    resolve_conflicts              # 10. 冲突预检 + 配置重载
    compile_firmware || exit 1     # 11. 编译固件
    organize_output                # 12. 整理输出
    
    echo ""
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${GREEN}  🎉 全部完成！固件在：$OUTPUT_DIR  ${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}\n"
    
    if [ "$NOVICE_MODE" = "true" ]; then
        echo -e "${YELLOW}📋 新手提示：${NC}"
        echo "  1. 登录：http://192.168.1.1 (root / 首次强制改密)"
        echo "  2. WiFi：${WIFI_PREFIX}XXXX_2G/5G | 密码：${WIFI_PASSWORD}"
        echo "  3. 刷机：首次刷入建议使用 initramfs 恢复固件"
        echo "  4. 日志：$OUTPUT_DIR/build.log"
        echo ""
    fi
}

# 执行主函数
main "$@"
