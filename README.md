# OpenWrt 官方源码自动化编译系统

基于 GitHub Actions 的 OpenWrt 官方固件自动编译方案

## 支持设备

- **Redmi AX6000** (MediaTek Filogic 830)
- **TP-LINK XDR6088** (MediaTek Filogic 830)

## 支持分支

- **main** - 主线开发版
- **openwrt-24.10** - 2024.10 稳定版 (内核 6.6)
- **openwrt-25.12** - 2025.12 最新版 (内核 6.12)

## 使用方法

1. Fork 本仓库
2. 进入 Actions → Builder OpenWrt Official
3. 选择参数：
   - 机型：redmi_ax6000 / tp-link_xdr6088
   - 分支：main / openwrt-24.10 / openwrt-25.12
   - 汉化：是/否
4. 点击 "Run workflow"
5. 编译完成后在 Release 下载固件

## 默认配置

- 管理地址：192.168.1.1
- 用户名：root
- 密码：首次登录强制修改
- WiFi：前缀 + MAC地址后4位_2G/5G

## 许可证

MIT License
