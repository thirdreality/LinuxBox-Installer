#!/bin/bash


HOME_ASSISTANT_VERSION=$(curl -s "https://api.github.com/repos/home-assistant/core/releases/latest" | jq -r '.tag_name')
echo "Latest home-assistant version: $HOME_ASSISTANT_VERSION"

MATTER_SERVER_VERSION=$(curl -s "https://api.github.com/repos/home-assistant-libs/python-matter-server/releases/latest" | jq -r '.tag_name')
echo "Latest matter-server version: $MATTER_SERVER_VERSION"

get_ha_dependencies() {
    local version="$1"
    local base_url="https://raw.githubusercontent.com/home-assistant/core/$version"
    
    echo "=== Home Assistant Core $version 完整依赖分析 ==="
    
    # Frontend 版本
    echo -e "\n📱 Frontend:"
    frontend_dep=$(curl -s "$base_url/homeassistant/components/frontend/manifest.json" | jq -r '.requirements[] | select(contains("home-assistant-frontend"))')
    echo "  $frontend_dep"
    
    # 核心 Python 依赖
    echo -e "\n🐍 核心 Python 依赖:"
    curl -s "$base_url/homeassistant/package_constraints.txt" | head -20
    
    # 检查是否有 Dockerfile 信息
    echo -e "\n🐳 Docker 基础镜像:"
    curl -s "$base_url/Dockerfile" | grep "FROM" | head -1
    
    # 获取版本发布信息
    echo -e "\n📋 版本发布信息:"
    release_info=$(curl -s "https://api.github.com/repos/home-assistant/core/releases/tags/$version")
    if [ "$release_info" != "null" ] && [ -n "$release_info" ]; then
        echo "$release_info" | jq -r '.published_at as $date | .name as $name | "发布日期: \($date), 名称: \($name)"'
    fi
}

# 使用示例
get_ha_dependencies "2025.8.2"