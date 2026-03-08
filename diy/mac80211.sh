#!/bin/sh
# ============================================================================
# 自定义 mac80211.sh - WiFi 自动配置 (TP-LINK_XXXX_5G/2G)
# 功能：自动检测无线设备，生成自定义 SSID + 启用加密 + 中国频段
# 适配：Lean OpenWrt + TL-XDR6088 / 其他 MediaTek 设备
# ============================================================================

append DRIVERS "mac80211"

# [保留原函数：lookup_phy / find_mac80211_phy / check_mac80211_device]
# ...（原函数代码保持不变，此处省略）...

lookup_phy() {
	[ -n "$phy" ] && {
		[ -d /sys/class/ieee80211/$phy ] && return
	}

	local devpath
	config_get devpath "$device" path
	[ -n "$devpath" ] && {
		phy="$(iwinfo nl80211 phyname "path=$devpath")"
		[ -n "$phy" ] && return
	}

	local macaddr="$(config_get "$device" macaddr | tr 'A-Z' 'a-z')"
	[ -n "$macaddr" ] && {
		for _phy in /sys/class/ieee80211/*; do
			[ -e "$_phy" ] || continue
			[ "$macaddr" = "$(cat ${_phy}/macaddress)" ] || continue
			phy="${_phy##*/}"
			return
		done
	}
	phy=
	return 0
}

find_mac80211_phy() {
	local device="$1"
	config_get phy "$device" phy
	lookup_phy
	[ -n "$phy" -a -d "/sys/class/ieee80211/$phy" ] || {
		echo "PHY for wifi device $1 not found"
		return 1
	}
	config_set "$device" phy "$phy"
	config_get macaddr "$device" macaddr
	[ -z "$macaddr" ] && {
		config_set "$device" macaddr "$(cat /sys/class/ieee80211/${phy}/macaddress)"
	}
	return 0
}

check_mac80211_device() {
	config_get phy "$1" phy
	[ -z "$phy" ] && {
		find_mac80211_phy "$1" >/dev/null || return 0
		config_get phy "$1" phy
	}
	[ "$phy" = "$dev" ] && found=1
}

__get_band_defaults() {
	local phy="$1"
	( iw phy "$phy" info; echo ) | awk '
BEGIN { bands = "" }
($1 == "Band" || $1 == "") && band {
        if (channel) {
		mode="NOHT"
		if (ht) mode="HT20"
		if (vht && band != "1:") mode="VHT80"
		if (he) mode="HE80"
		if (he && band == "1:") mode="HE20"
                sub("\\[", "", channel)
                sub("\\]", "", channel)
                bands = bands band channel ":" mode " "
        }
        band=""
}
$1 == "Band" { band = $2; channel = ""; vht = ""; ht = ""; he = "" }
$0 ~ "Capabilities:" { ht=1 }
$0 ~ "VHT Capabilities" { vht=1 }
$0 ~ "HE Iftypes" { he=1 }
$1 == "*" && $3 == "MHz" && $0 !~ /disabled/ && band && !channel { channel = $4 }
END { print bands }'
}

get_band_defaults() {
	local phy="$1"
	for c in $(__get_band_defaults "$phy"); do
		local band="${c%%:*}"
		c="${c#*:}"
		local chan="${c%%:*}"
		c="${c#*:}"
		local mode="${c%%:*}"
		case "$band" in
			1) band=2g;; 2) band=5g;; 3) band=60g;; 4) band=6g;; *) band="";;
		esac
		[ -n "$band" ] || continue
		[ -n "$mode_band" -a "$band" = "6g" ] && return
		mode_band="$band"; channel="$chan"; htmode="$mode"
	done
}

# ============================================================================
# 🔧 主函数：检测并配置无线设备（优化版）
# ============================================================================
detect_mac80211() {
	# 🔐 防重复执行标记：如果已配置过，直接返回
	[ -f "/etc/.wifi_mac80211_customized" ] && return 0
	
	devidx=0
	config_load wireless
	
	# 计算已有 radio 数量
	while :; do
		config_get type "radio$devidx" type
		[ -n "$type" ] || break
		devidx=$(($devidx + 1))
	done

	for _dev in /sys/class/ieee80211/*; do
		[ -e "$_dev" ] || continue
		dev="${_dev##*/}"
		found=0
		config_foreach check_mac80211_device wifi-device
		[ "$found" -gt 0 ] && continue

		mode_band=""; channel=""; htmode=""; ht_capab=""
		get_band_defaults "$dev"
		path="$(iwinfo nl80211 path "$dev")"
		
		# 设备标识（path 优先，否则用 macaddr）
		if [ -n "$path" ]; then
			dev_id="set wireless.radio${devidx}.path='$path'"
		else
			dev_id="set wireless.radio${devidx}.macaddr=$(cat /sys/class/ieee80211/${dev}/macaddress)"
		fi
		
		# 🎯 频段后缀：5G → _5G, 其他 → _2G
		if [ "$mode_band" = "5g" ]; then
			band_suffix="_5G"
		else
			band_suffix="_2G"
		fi

		# 🔑 提取 MAC 地址最后 4 位（大写）
		mac_suffix=$(cat /sys/class/ieee80211/${dev}/macaddress | awk -F ":" '{print toupper($(NF-1)$(NF))}')

		# 📡 应用配置（启用加密 + 中国频段 + 自定义 SSID）
		uci -q batch <<-EOF
			set wireless.radio${devidx}=wifi-device
			set wireless.radio${devidx}.type=mac80211
			${dev_id}
			set wireless.radio${devidx}.channel=${channel}
			set wireless.radio${devidx}.band=${mode_band}
			set wireless.radio${devidx}.htmode=$htmode
			set wireless.radio${devidx}.disabled=0
			set wireless.radio${devidx}.country=CN

			set wireless.default_radio${devidx}=wifi-iface
			set wireless.default_radio${devidx}.device=radio${devidx}
			set wireless.default_radio${devidx}.network=lan
			set wireless.default_radio${devidx}.mode=ap
			set wireless.default_radio${devidx}.ssid=TP-LINK_${mac_suffix}${band_suffix}
			set wireless.default_radio${devidx}.encryption=psk2
			set wireless.default_radio${devidx}.key=1234567890
EOF
		uci -q commit wireless
		devidx=$(($devidx + 1))
	done
	
	# ✅ 标记已配置，避免重复执行
	touch /etc/.wifi_mac80211_customized
	return 0
}
