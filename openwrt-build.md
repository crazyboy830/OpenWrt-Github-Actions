# ✅ 使用说明
## 1. 准备环境
```
# 克隆官方 OpenWrt 源码
git clone --single-branch https://github.com/openwrt/openwrt.git
cd openwrt

# 将脚本文件放入对应位置
# openwrt-build.sh → openwrt/ 根目录
# diy/ 目录 → openwrt/diy/
```
   
   
## 2. 执行编译
```
# 赋予执行权限
chmod +x openwrt-build.sh

# 运行脚本
./openwrt-build.sh

# 按提示选择：
# - 是否启用新手模式（自动安装依赖 + 配置第三方源）
# - 选择机型（ax6000 / xdr6088 / custom）
# - 选择配置版本（full / mini / custom）
# - 等待编译完成...
```

## 3. 获取固件
```
# 编译完成后，固件位于：
./output/

# 包含文件：
# - OpenWrt-redmi-ax6000-20260512-sysupgrade.itb  # 常规升级固件
# - OpenWrt-redmi-ax6000-20260512-initramfs-recovery.itb  # 救砖固件
# - sha256sums.txt  # 校验和
# - build-ax6000-20260512.config  # 编译配置备份
# - packages.tar.gz  # 插件包集合（可选）
```

