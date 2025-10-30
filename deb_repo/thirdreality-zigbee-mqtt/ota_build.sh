#!/bin/bash

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查命令是否存在
check_command() {
    if ! command -v $1 &> /dev/null; then
        log_error "命令 '$1' 未找到，请先安装"
        exit 1
    fi
}

# 使用说明
usage() {
    cat << EOF
使用方法: $0 <old_deb_file> <new_deb_file> [output_name]

参数说明:
  old_deb_file   : 旧版本的 deb 文件路径 (baseline)
  new_deb_file   : 新版本的 deb 文件路径
  output_name    : 输出的差分包名称（可选，默认自动生成）

示例:
  $0 app_2025.10.0.deb app_2025.10.1.deb
  $0 app_2025.10.0.deb app_2025.10.1.deb my_diff_package

EOF
    exit 1
}

# 计算文件 SHA256
calculate_checksum() {
    sha256sum "$1" | awk '{print $1}'
}

# 获取文件权限（八进制格式）
get_file_permissions() {
    stat -c "%a" "$1"
}

# 从 deb 文件中提取版本号
extract_version_from_deb() {
    local deb_file=$1
    dpkg-deb --info "$deb_file" | grep "Version:" | awk '{print $2}' | head -n 1
}

# 清理函数
cleanup() {
    log_info "清理临时文件..."
    if [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
    fi
}

# 主函数
main() {
    # 检查参数
    if [ $# -lt 2 ]; then
        usage
    fi

    OLD_DEB="$1"
    NEW_DEB="$2"
    OUTPUT_NAME="${3:-}"

    # 检查输入文件是否存在
    if [ ! -f "$OLD_DEB" ]; then
        log_error "旧版本 deb 文件不存在: $OLD_DEB"
        exit 1
    fi

    if [ ! -f "$NEW_DEB" ]; then
        log_error "新版本 deb 文件不存在: $NEW_DEB"
        exit 1
    fi

    # 检查必要的命令
    log_info "检查必要的工具..."
    check_command dpkg-deb
    check_command sha256sum
    check_command jq
    check_command zip

    # 提取版本号
    log_info "提取版本信息..."
    OLD_VERSION=$(extract_version_from_deb "$OLD_DEB")
    NEW_VERSION=$(extract_version_from_deb "$NEW_DEB")
    
    if [ -z "$OLD_VERSION" ] || [ -z "$NEW_VERSION" ]; then
        log_error "无法从 deb 文件中提取版本号"
        exit 1
    fi

    log_info "旧版本: $OLD_VERSION"
    log_info "新版本: $NEW_VERSION"

    # 设置输出名称
    if [ -z "$OUTPUT_NAME" ]; then
        OUTPUT_NAME="${NEW_VERSION}_diff_from_${OLD_VERSION}"
    fi

    # 创建工作目录
    WORK_DIR="./tmp_diff_build_$$"
    OLD_DIR="$WORK_DIR/old"
    NEW_DIR="$WORK_DIR/new"
    DIFF_DIR="$WORK_DIR/diff_package"
    FILES_DIR="$DIFF_DIR/files"

    log_info "创建工作目录: $WORK_DIR"
    mkdir -p "$OLD_DIR" "$NEW_DIR" "$FILES_DIR"

    # 注册清理函数
    trap cleanup EXIT

    # 解压 deb 包
    log_info "解压旧版本 deb 包..."
    dpkg-deb -x "$OLD_DEB" "$OLD_DIR"
    
    log_info "解压新版本 deb 包..."
    dpkg-deb -x "$NEW_DEB" "$NEW_DIR"

    # 初始化 manifest 数据结构
    log_info "分析文件差异..."
    
    ADD_FILES=()
    MODIFY_FILES=()
    DELETE_FILES=()

    # 查找新增和修改的文件
    while IFS= read -r -d '' new_file; do
        # 获取相对路径
        rel_path="${new_file#$NEW_DIR/}"
        old_file="$OLD_DIR/$rel_path"

        # 跳过目录
        if [ -d "$new_file" ]; then
            continue
        fi

        if [ ! -f "$old_file" ]; then
            # 新增文件
            ADD_FILES+=("$rel_path")
            log_info "  [新增] $rel_path"
        else
            # 检查文件是否有变化
            new_checksum=$(calculate_checksum "$new_file")
            old_checksum=$(calculate_checksum "$old_file")
            
            if [ "$new_checksum" != "$old_checksum" ]; then
                # 修改文件
                MODIFY_FILES+=("$rel_path")
                log_info "  [修改] $rel_path"
            fi
        fi
    done < <(find "$NEW_DIR" -type f -print0)

    # 查找删除的文件
    while IFS= read -r -d '' old_file; do
        rel_path="${old_file#$OLD_DIR/}"
        new_file="$NEW_DIR/$rel_path"

        # 跳过目录
        if [ -d "$old_file" ]; then
            continue
        fi

        if [ ! -f "$new_file" ]; then
            # 删除的文件
            DELETE_FILES+=("$rel_path")
            log_info "  [删除] $rel_path"
        fi
    done < <(find "$OLD_DIR" -type f -print0)

    log_info "差异统计: 新增=${#ADD_FILES[@]}, 修改=${#MODIFY_FILES[@]}, 删除=${#DELETE_FILES[@]}"

    # 复制新增和修改的文件到差分包
    log_info "复制变更文件..."
    for file in "${ADD_FILES[@]}" "${MODIFY_FILES[@]}"; do
        src_file="$NEW_DIR/$file"
        dst_file="$FILES_DIR/$file"
        
        # 创建目标目录
        mkdir -p "$(dirname "$dst_file")"
        
        # 复制文件并保持权限
        cp -p "$src_file" "$dst_file"
    done

    # 生成 manifest.json
    log_info "生成 manifest.json..."
    
    MANIFEST_FILE="$DIFF_DIR/manifest.json"
    
    # 开始构建 JSON
    cat > "$MANIFEST_FILE" << EOF
{
  "from_version": "$OLD_VERSION",
  "to_version": "$NEW_VERSION",
  "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "operations": {
    "add": [
EOF

    # 添加新增文件信息
    first=true
    for file in "${ADD_FILES[@]}"; do
        if [ "$first" = false ]; then
            echo "," >> "$MANIFEST_FILE"
        fi
        first=false
        
        file_path="$NEW_DIR/$file"
        checksum=$(calculate_checksum "$file_path")
        size=$(stat -c %s "$file_path")
        perms=$(get_file_permissions "$file_path")
        
        cat >> "$MANIFEST_FILE" << EOF
      {
        "path": "$file",
        "checksum": "$checksum",
        "size": $size,
        "permissions": "$perms"
      }
EOF
    done

    cat >> "$MANIFEST_FILE" << EOF

    ],
    "modify": [
EOF

    # 添加修改文件信息
    first=true
    for file in "${MODIFY_FILES[@]}"; do
        if [ "$first" = false ]; then
            echo "," >> "$MANIFEST_FILE"
        fi
        first=false
        
        new_file_path="$NEW_DIR/$file"
        old_file_path="$OLD_DIR/$file"
        new_checksum=$(calculate_checksum "$new_file_path")
        old_checksum=$(calculate_checksum "$old_file_path")
        size=$(stat -c %s "$new_file_path")
        perms=$(get_file_permissions "$new_file_path")
        
        cat >> "$MANIFEST_FILE" << EOF
      {
        "path": "$file",
        "checksum": "$new_checksum",
        "old_checksum": "$old_checksum",
        "size": $size,
        "permissions": "$perms"
      }
EOF
    done

    cat >> "$MANIFEST_FILE" << EOF

    ],
    "delete": [
EOF

    # 添加删除文件信息
    first=true
    for file in "${DELETE_FILES[@]}"; do
        if [ "$first" = false ]; then
            echo "," >> "$MANIFEST_FILE"
        fi
        first=false
        
        old_file_path="$OLD_DIR/$file"
        old_checksum=$(calculate_checksum "$old_file_path")
        
        cat >> "$MANIFEST_FILE" << EOF
      {
        "path": "$file",
        "old_checksum": "$old_checksum"
      }
EOF
    done

    cat >> "$MANIFEST_FILE" << EOF

    ]
  },
  "prerequisites": {
    "min_disk_space": 0
  }
}
EOF

    # 验证 JSON 格式
    if ! jq empty "$MANIFEST_FILE" 2>/dev/null; then
        log_error "生成的 manifest.json 格式不正确"
        exit 1
    fi

    # 计算 manifest 的校验和并添加到文件中
    MANIFEST_CHECKSUM=$(calculate_checksum "$MANIFEST_FILE")
    jq --arg checksum "$MANIFEST_CHECKSUM" '.checksum = $checksum' "$MANIFEST_FILE" > "$MANIFEST_FILE.tmp"
    mv "$MANIFEST_FILE.tmp" "$MANIFEST_FILE"

    log_info "Manifest 校验和: $MANIFEST_CHECKSUM"

    # 打包为 zip 文件
    OUTPUT_FILE="${OUTPUT_NAME}.zip"
    log_info "打包差分包: $OUTPUT_FILE"
    
    cd "$DIFF_DIR"
    zip -r "../../$OUTPUT_FILE" . -q
    cd - > /dev/null

    # 计算差分包校验和
    PACKAGE_CHECKSUM=$(calculate_checksum "$OUTPUT_FILE")
    PACKAGE_SIZE=$(stat -c %s "$OUTPUT_FILE")

    # 输出摘要信息
    echo ""
    log_info "================================"
    log_info "差分包生成完成！"
    log_info "================================"
    log_info "输出文件: $OUTPUT_FILE"
    log_info "文件大小: $(numfmt --to=iec-i --suffix=B $PACKAGE_SIZE)"
    log_info "SHA256: $PACKAGE_CHECKSUM"
    log_info "从版本: $OLD_VERSION"
    log_info "到版本: $NEW_VERSION"
    log_info "新增文件: ${#ADD_FILES[@]}"
    log_info "修改文件: ${#MODIFY_FILES[@]}"
    log_info "删除文件: ${#DELETE_FILES[@]}"
    log_info "================================"

    # 生成摘要文件
    SUMMARY_FILE="${OUTPUT_NAME}_summary.txt"
    cat > "$SUMMARY_FILE" << EOF
差分包摘要信息
=====================================
文件名称: $OUTPUT_FILE
文件大小: $(numfmt --to=iec-i --suffix=B $PACKAGE_SIZE)
SHA256: $PACKAGE_CHECKSUM
生成时间: $(date)

版本信息:
  从版本: $OLD_VERSION
  到版本: $NEW_VERSION

变更统计:
  新增文件: ${#ADD_FILES[@]}
  修改文件: ${#MODIFY_FILES[@]}
  删除文件: ${#DELETE_FILES[@]}

详细变更列表:
EOF

    if [ ${#ADD_FILES[@]} -gt 0 ]; then
        echo "" >> "$SUMMARY_FILE"
        echo "新增文件:" >> "$SUMMARY_FILE"
        printf "  - %s\n" "${ADD_FILES[@]}" >> "$SUMMARY_FILE"
    fi

    if [ ${#MODIFY_FILES[@]} -gt 0 ]; then
        echo "" >> "$SUMMARY_FILE"
        echo "修改文件:" >> "$SUMMARY_FILE"
        printf "  - %s\n" "${MODIFY_FILES[@]}" >> "$SUMMARY_FILE"
    fi

    if [ ${#DELETE_FILES[@]} -gt 0 ]; then
        echo "" >> "$SUMMARY_FILE"
        echo "删除文件:" >> "$SUMMARY_FILE"
        printf "  - %s\n" "${DELETE_FILES[@]}" >> "$SUMMARY_FILE"
    fi

    log_info "摘要信息已保存到: $SUMMARY_FILE"
}

# 执行主函数
main "$@"
