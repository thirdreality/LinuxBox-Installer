#!/bin/bash

current_dir=$(pwd)
output_dir="${current_dir}/output"
version="4.2.0"  # OpenHAB version

REBUILD=false
CLEAN=false

SCRIPT="R3"
print_info() { echo -e "\e[1;34m[${SCRIPT}] INFO:\e[0m $1"; }
print_error() { echo -e "\e[1;31m[${SCRIPT}] ERROR:\e[0m $1"; }

print_info "Build script for ThirdReality OpenHAB"
print_info "Usage: Build.sh [--rebuild] [--clean]"
print_info "Options:"
print_info "  --rebuild: Rebuild the env"
print_info "  --clean: Clean the output directory and remove the env"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --rebuild) REBUILD=true ;;
        --clean) CLEAN=true ;;
        *) print_info "未知参数: $1" >&2; exit 1 ;;
    esac
    shift
done

# 创建必要的目录
mkdir -p ${current_dir}/deb/zulu
mkdir -p ${current_dir}/deb/openhab

# 安装 OpenHAB 的函数
install_openhab() {
    print_info "开始安装 OpenHAB..."
    
    # 检查并设置 GPG 密钥
    if [ ! -f "/usr/share/keyrings/openhab.gpg" ]; then
        print_info "设置 OpenHAB GPG 密钥..."
        curl -fsSL "https://openhab.jfrog.io/artifactory/api/gpg/key/public" | gpg --dearmor > openhab.gpg
        mkdir -p /usr/share/keyrings
        mv openhab.gpg /usr/share/keyrings
        chmod u=rw,g=r,o=r /usr/share/keyrings/openhab.gpg
        
        print_info "添加 OpenHAB 软件源..."
        echo 'deb [signed-by=/usr/share/keyrings/openhab.gpg] https://openhab.jfrog.io/artifactory/openhab-linuxpkg stable main' | tee /etc/apt/sources.list.d/openhab.list
    else
        print_info "OpenHAB GPG 密钥已存在，跳过设置"
    fi
    
    # 更新软件包列表
    print_info "更新软件包列表..."
    apt-get update
    apt-get clean
    
    # 下载 Zulu JDK
    print_info "下载 Zulu21 JDK..."
    apt-get install --download-only zulu21-jdk
    
    # 拷贝 Zulu JDK deb 包
    print_info "拷贝 Zulu JDK deb 包到 ${current_dir}/deb/zulu/"
    cp /var/cache/apt/archives/*.deb ${current_dir}/deb/zulu/ 2>/dev/null || true
    
    # 清理缓存并下载 OpenHAB
    apt-get clean
    print_info "下载 OpenHAB 和 OpenHAB 插件..."
    apt-get install --download-only openhab openhab-addons
    
    # 拷贝 OpenHAB deb 包
    print_info "拷贝 OpenHAB deb 包到 ${current_dir}/deb/openhab/"
    cp /var/cache/apt/archives/*.deb ${current_dir}/deb/openhab/ 2>/dev/null || true
    
    # 安装软件包
    print_info "安装 Zulu JDK, OpenHAB 和 OpenHAB 插件..."
    #apt-get install -y zulu21-jdk openhab openhab-addons
    
    # 清理安装的软件包（用于打包）
    print_info "清理安装的软件包..."
    #apt-get purge -y zulu21-jdk openhab openhab-addons
    
    print_info "OpenHAB 安装和清理完成"
}

# 清理函数
clean_build() {
    print_info "清理构建环境..."
    rm -rf ${output_dir} > /dev/null 2>&1
    rm -rf ${current_dir}/deb > /dev/null 2>&1
    rm -f ${current_dir}/hacore_*.deb > /dev/null 2>&1
    print_info "清理完成"
}

# 主构建逻辑
if [ "$CLEAN" = true ]; then
    clean_build
    exit 0
fi

if [ "$REBUILD" = true ]; then
    print_info "重建模式：先清理再构建"
    clean_build
fi

# 执行 OpenHAB 安装过程
install_openhab


# 构建 DEB 包
print_info "开始构建 openhab_${version}.deb ..."
if [ -d "${output_dir}" ]; then
    dpkg-deb --build ${output_dir} ${current_dir}/openhab_${version}.deb
    print_info "构建 openhab_${version}.deb 完成!"
else
    print_error "输出目录 ${output_dir} 不存在，请检查构建过程"
    exit 1
fi

# 可选：清理临时文件（注释掉以保留调试信息）
# rm -rf ${output_dir}/srv > /dev/null 2>&1
# rm -rf ${output_dir}/usr > /dev/null 2>&1
# rm -rf ${output_dir}/lib > /dev/null 2>&1
# rm -rf ${output_dir} > /dev/null 2>&1

print_info "ThirdReality OpenHAB 构建流程完成!"
print_info "生成的文件："
print_info "  - openhab_${version}.deb"
print_info "  - deb/zulu/ (Zulu JDK deb 包)"
print_info "  - deb/openhab/ (OpenHAB deb 包)"

