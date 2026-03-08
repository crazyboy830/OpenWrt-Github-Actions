# openwrt-onekey-xdr6088
本地一键编译XDR6088 opwenwrt 固件。

# 🔹 首次完整编译
./openwrt-onekey.sh --clean

# 🔹 日常快速编译
./openwrt-onekey.sh --skip-deps

# 🔹 低内存编译
./openwrt-onekey.sh --skip-deps --threads 2

# 🔹 只配置不编译（测试）
./openwrt-onekey.sh --no-compile --skip-deps

# 🔹 查看帮助
./openwrt-onekey.sh --help

# 🔹 查看固件文件
ls -lh output/

# 🔹 查看编译日志
tail -100 openwrt-build/openwrt/build.log

# 🔹 清理编译产物（保留源码）
cd openwrt-build/openwrt && make dirclean

# 🔹 完全重来（删除所有）
rm -rf openwrt-build output

🔄 后续更新固件
# 1. 拉取最新源码 + 重新编译
./openwrt-onekey.sh --skip-deps

# 2. 编译完成后，刷入新固件（方法同上）

# 3. 如需保留配置，刷写时勾选"保留配置"
