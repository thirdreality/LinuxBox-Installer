#!/bin/bash
# OTA 升级应用脚本
# 用于应用由 ota_build.sh 生成的差分升级包

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 检查命令是否存在
check_command() {
    if ! command -v $1 &> /dev/null; then
        log_error "命令 '$1' 未找到，请先安装"
        exit 1
    fi
}

# 计算文件 SHA256
calculate_checksum() {
    sha256sum "$1" | awk '{print $1}'
}

# 使用说明
usage() {
    cat << EOF
使用方法: $0 <ota_package.zip> [options]

参数说明:
  ota_package.zip    : OTA 升级包文件路径

选项:
  --dry-run          : 仅检查，不实际应用升级
  --no-backup        : 不创建备份（不推荐）
  --force            : 强制升级（跳过版本检查）
  --keep-services    : 升级过程中不停止服务（可能导致问题）

示例:
  $0 2025.10.2_diff_from_2025.10.1.zip
  $0 upgrade_package.zip --dry-run
  $0 upgrade_package.zip --force

EOF
    exit 1
}

# 清理函数
cleanup() {
    log_info "清理临时文件..."
    if [ -d "$WORK_DIR" ]; then
        rm -rf "$WORK_DIR"
    fi
}

# 回滚函数
rollback() {
    log_error "升级失败，正在回滚..."
    
    if [ -z "$BACKUP_DIR" ] || [ ! -d "$BACKUP_DIR" ]; then
        log_error "备份目录不存在，无法回滚"
        return 1
    fi
    
    log_info "从备份恢复文件: $BACKUP_DIR"
    
    # 恢复备份的文件
    if [ -f "$BACKUP_DIR/file_list.txt" ]; then
        while IFS= read -r file; do
            if [ -f "$BACKUP_DIR/$file" ]; then
                mkdir -p "$(dirname "/$file")"
                cp -p "$BACKUP_DIR/$file" "/$file"
                log_info "  恢复: $file"
            fi
        done < "$BACKUP_DIR/file_list.txt"
    fi
    
    log_info "回滚完成"
    
    # 重启服务
    if [ "$SERVICES_STOPPED" = true ]; then
        systemctl start home-assistant.service || true
        systemctl start matter-server.service || true
    fi
}

# 停止服务
stop_services() {
    if [ "$KEEP_SERVICES" = true ]; then
        log_warn "跳过停止服务（--keep-services 已设置）"
        return 0
    fi
    
    log_step "停止相关服务..."
    
    if systemctl is-active --quiet home-assistant.service; then
        systemctl stop home-assistant.service
        log_info "已停止 home-assistant.service"
        SERVICES_STOPPED=true
    fi
    
    if systemctl is-active --quiet matter-server.service; then
        systemctl stop matter-server.service
        log_info "已停止 matter-server.service"
        SERVICES_STOPPED=true
    fi
    
    # 等待服务完全停止
    sleep 2
}

# 启动服务
start_services() {
    if [ "$KEEP_SERVICES" = true ]; then
        return 0
    fi
    
    log_step "启动服务..."
    
    systemctl start home-assistant.service || {
        log_error "启动 home-assistant.service 失败"
        return 1
    }
    
    systemctl start matter-server.service || {
        log_error "启动 matter-server.service 失败"
        return 1
    }
    
    log_info "服务已启动"
    
    # 等待服务就绪
    sleep 5
    
    # 验证服务状态
    if ! systemctl is-active --quiet home-assistant.service; then
        log_error "home-assistant.service 未能成功启动"
        return 1
    fi
    
    if ! systemctl is-active --quiet matter-server.service; then
        log_warn "matter-server.service 未能成功启动"
    fi
    
    return 0
}

# 创建备份
create_backup() {
    if [ "$NO_BACKUP" = true ]; then
        log_warn "跳过创建备份（--no-backup 已设置）"
        return 0
    fi
    
    log_step "创建升级前备份..."
    
    BACKUP_DIR="/var/lib/homeassistant/ota-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    # 备份将要修改和删除的文件
    local file_list="$BACKUP_DIR/file_list.txt"
    > "$file_list"
    
    # 备份要修改的文件
    if [ -f "$MANIFEST_FILE" ]; then
        jq -r '.operations.modify[].path' "$MANIFEST_FILE" | while read -r file; do
            if [ -f "/$file" ]; then
                mkdir -p "$BACKUP_DIR/$(dirname "$file")"
                cp -p "/$file" "$BACKUP_DIR/$file"
                echo "$file" >> "$file_list"
            fi
        done
    fi
    
    # 备份要删除的文件
    if [ -f "$MANIFEST_FILE" ]; then
        jq -r '.operations.delete[].path' "$MANIFEST_FILE" 2>/dev/null | while read -r file; do
            if [ -f "/$file" ]; then
                mkdir -p "$BACKUP_DIR/$(dirname "$file")"
                cp -p "/$file" "$BACKUP_DIR/$file"
                echo "$file" >> "$file_list"
            fi
        done
    fi
    
    # 保存当前包版本信息
    dpkg -l | grep thirdreality > "$BACKUP_DIR/package-version.txt" || true
    
    log_info "备份已创建: $BACKUP_DIR"
    echo "$BACKUP_DIR" > /var/lib/homeassistant/last-ota-backup.txt
}

# 检查系统状态
check_system_status() {
    log_step "检查系统状态..."
    
    # 检查磁盘空间
    AVAILABLE_SPACE=$(df /srv | awk 'NR==2 {print $4}')
    REQUIRED_SPACE=524288  # 512MB in KB
    
    if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
        log_error "磁盘空间不足. 需要: 512MB, 可用: $((AVAILABLE_SPACE/1024))MB"
        exit 1
    fi
    
    log_info "磁盘空间检查通过: $((AVAILABLE_SPACE/1024))MB 可用"
    
    # 检查当前安装的版本
    CURRENT_VERSION=$(dpkg -l | grep thirdreality-hacore | awk '{print $3}')
    if [ -z "$CURRENT_VERSION" ]; then
        log_error "未检测到已安装的 thirdreality-hacore 包"
        exit 1
    fi
    
    log_info "当前版本: $CURRENT_VERSION"
}

# 验证升级包
verify_package() {
    local package_file="$1"
    
    log_step "验证升级包..."
    
    # 检查文件是否存在
    if [ ! -f "$package_file" ]; then
        log_error "升级包文件不存在: $package_file"
        exit 1
    fi
    
    # 解压升级包
    WORK_DIR="./tmp_ota_apply_$$"
    mkdir -p "$WORK_DIR"
    
    log_info "解压升级包..."
    unzip -q "$package_file" -d "$WORK_DIR" || {
        log_error "解压升级包失败"
        exit 1
    }
    
    # 检查 manifest.json
    MANIFEST_FILE="$WORK_DIR/manifest.json"
    if [ ! -f "$MANIFEST_FILE" ]; then
        log_error "升级包中未找到 manifest.json"
        exit 1
    fi
    
    # 验证 JSON 格式
    if ! jq empty "$MANIFEST_FILE" 2>/dev/null; then
        log_error "manifest.json 格式无效"
        exit 1
    fi
    
    # 读取版本信息
    FROM_VERSION=$(jq -r '.from_version' "$MANIFEST_FILE")
    TO_VERSION=$(jq -r '.to_version' "$MANIFEST_FILE")
    
    log_info "升级包信息:"
    log_info "  从版本: $FROM_VERSION"
    log_info "  到版本: $TO_VERSION"
    log_info "  创建时间: $(jq -r '.created_at' "$MANIFEST_FILE")"
    
    # 检查版本匹配
    if [ "$FORCE_UPGRADE" != true ]; then
        if [ "$CURRENT_VERSION" != "$FROM_VERSION" ]; then
            log_error "版本不匹配!"
            log_error "  当前版本: $CURRENT_VERSION"
            log_error "  升级包要求: $FROM_VERSION"
            log_error "使用 --force 可以跳过此检查（风险自负）"
            exit 1
        fi
    else
        log_warn "强制升级模式：跳过版本检查"
    fi
    
    # 统计变更
    ADD_COUNT=$(jq '.operations.add | length' "$MANIFEST_FILE")
    MODIFY_COUNT=$(jq '.operations.modify | length' "$MANIFEST_FILE")
    DELETE_COUNT=$(jq '.operations.delete | length' "$MANIFEST_FILE")
    
    log_info "变更统计:"
    log_info "  新增文件: $ADD_COUNT"
    log_info "  修改文件: $MODIFY_COUNT"
    log_info "  删除文件: $DELETE_COUNT"
}

# 应用升级
apply_upgrade() {
    log_step "应用升级..."
    
    local files_dir="$WORK_DIR/files"
    local success=true
    
    # 1. 删除文件
    if [ "$DELETE_COUNT" -gt 0 ]; then
        log_info "删除文件..."
        jq -r '.operations.delete[].path' "$MANIFEST_FILE" | while read -r file; do
            if [ -f "/$file" ]; then
                rm -f "/$file" && log_info "  已删除: $file" || {
                    log_error "  删除失败: $file"
                    success=false
                }
            fi
        done
    fi
    
    # 2. 添加新文件
    if [ "$ADD_COUNT" -gt 0 ]; then
        log_info "添加新文件..."
        jq -c '.operations.add[]' "$MANIFEST_FILE" | while read -r item; do
            file_path=$(echo "$item" | jq -r '.path')
            checksum=$(echo "$item" | jq -r '.checksum')
            permissions=$(echo "$item" | jq -r '.permissions')
            
            src_file="$files_dir/$file_path"
            dst_file="/$file_path"
            
            if [ ! -f "$src_file" ]; then
                log_error "  源文件不存在: $file_path"
                success=false
                continue
            fi
            
            # 验证校验和
            actual_checksum=$(calculate_checksum "$src_file")
            if [ "$actual_checksum" != "$checksum" ]; then
                log_error "  校验和不匹配: $file_path"
                success=false
                continue
            fi
            
            # 复制文件
            mkdir -p "$(dirname "$dst_file")"
            cp -p "$src_file" "$dst_file" && {
                chmod "$permissions" "$dst_file"
                log_info "  已添加: $file_path"
            } || {
                log_error "  添加失败: $file_path"
                success=false
            }
        done
    fi
    
    # 3. 修改文件
    if [ "$MODIFY_COUNT" -gt 0 ]; then
        log_info "修改文件..."
        jq -c '.operations.modify[]' "$MANIFEST_FILE" | while read -r item; do
            file_path=$(echo "$item" | jq -r '.path')
            new_checksum=$(echo "$item" | jq -r '.checksum')
            old_checksum=$(echo "$item" | jq -r '.old_checksum')
            permissions=$(echo "$item" | jq -r '.permissions')
            
            src_file="$files_dir/$file_path"
            dst_file="/$file_path"
            
            # 验证旧文件校验和（确保没被修改过）
            if [ -f "$dst_file" ]; then
                actual_old_checksum=$(calculate_checksum "$dst_file")
                if [ "$actual_old_checksum" != "$old_checksum" ] && [ "$FORCE_UPGRADE" != true ]; then
                    log_warn "  文件已被修改，跳过: $file_path"
                    continue
                fi
            fi
            
            if [ ! -f "$src_file" ]; then
                log_error "  源文件不存在: $file_path"
                success=false
                continue
            fi
            
            # 验证新文件校验和
            actual_new_checksum=$(calculate_checksum "$src_file")
            if [ "$actual_new_checksum" != "$new_checksum" ]; then
                log_error "  校验和不匹配: $file_path"
                success=false
                continue
            fi
            
            # 替换文件
            mkdir -p "$(dirname "$dst_file")"
            cp -p "$src_file" "$dst_file" && {
                chmod "$permissions" "$dst_file"
                log_info "  已修改: $file_path"
            } || {
                log_error "  修改失败: $file_path"
                success=false
            }
        done
    fi
    
    if [ "$success" = false ]; then
        log_error "升级过程中出现错误"
        return 1
    fi
    
    log_info "文件升级完成"
    return 0
}

# 验证升级结果
verify_upgrade() {
    log_step "验证升级结果..."
    
    # 验证添加的文件
    jq -c '.operations.add[]' "$MANIFEST_FILE" | while read -r item; do
        file_path=$(echo "$item" | jq -r '.path')
        checksum=$(echo "$item" | jq -r '.checksum')
        
        if [ ! -f "/$file_path" ]; then
            log_error "  文件不存在: $file_path"
            return 1
        fi
        
        actual_checksum=$(calculate_checksum "/$file_path")
        if [ "$actual_checksum" != "$checksum" ]; then
            log_error "  校验和不匹配: $file_path"
            return 1
        fi
    done
    
    # 验证修改的文件
    jq -c '.operations.modify[]' "$MANIFEST_FILE" | while read -r item; do
        file_path=$(echo "$item" | jq -r '.path')
        checksum=$(echo "$item" | jq -r '.checksum')
        
        if [ ! -f "/$file_path" ]; then
            log_error "  文件不存在: $file_path"
            return 1
        fi
        
        actual_checksum=$(calculate_checksum "/$file_path")
        if [ "$actual_checksum" != "$checksum" ]; then
            log_error "  校验和不匹配: $file_path"
            return 1
        fi
    done
    
    log_info "升级验证通过"
    return 0
}

# 记录升级日志
log_upgrade_result() {
    local status="$1"
    
    UPGRADE_LOG_DIR="/var/lib/homeassistant/upgrade-logs"
    mkdir -p "$UPGRADE_LOG_DIR"
    
    UPGRADE_LOG="$UPGRADE_LOG_DIR/ota-upgrade-$(date +%Y%m%d-%H%M%S).log"
    
    {
        echo "========================================"
        echo "OTA Upgrade Log"
        echo "========================================"
        echo "Time: $(date)"
        echo "Status: $status"
        echo "From Version: $FROM_VERSION"
        echo "To Version: $TO_VERSION"
        echo "Package: $OTA_PACKAGE"
        if [ -n "$BACKUP_DIR" ]; then
            echo "Backup: $BACKUP_DIR"
        fi
        echo "========================================"
    } > "$UPGRADE_LOG"
    
    log_info "升级日志已保存: $UPGRADE_LOG"
}

# 主函数
main() {
    # 参数解析
    if [ $# -lt 1 ]; then
        usage
    fi
    
    OTA_PACKAGE="$1"
    shift
    
    DRY_RUN=false
    NO_BACKUP=false
    FORCE_UPGRADE=false
    KEEP_SERVICES=false
    SERVICES_STOPPED=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                DRY_RUN=true
                ;;
            --no-backup)
                NO_BACKUP=true
                ;;
            --force)
                FORCE_UPGRADE=true
                ;;
            --keep-services)
                KEEP_SERVICES=true
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_error "未知选项: $1"
                usage
                ;;
        esac
        shift
    done
    
    # 检查必要工具
    log_info "检查必要工具..."
    check_command jq
    check_command unzip
    check_command sha256sum
    
    # 注册清理函数
    trap cleanup EXIT
    
    # 检查系统状态
    check_system_status
    
    # 验证升级包
    verify_package "$OTA_PACKAGE"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "=============================================="
        log_info "模拟运行完成 (--dry-run)"
        log_info "升级包验证通过，可以应用此升级"
        log_info "=============================================="
        exit 0
    fi
    
    # 创建备份
    create_backup
    
    # 停止服务
    stop_services
    
    # 应用升级
    if ! apply_upgrade; then
        log_error "升级失败"
        rollback
        log_upgrade_result "FAILED"
        exit 1
    fi
    
    # 验证升级
    if ! verify_upgrade; then
        log_error "升级验证失败"
        rollback
        log_upgrade_result "FAILED"
        exit 1
    fi
    
    # 启动服务
    if ! start_services; then
        log_warn "服务启动失败，可能需要手动干预"
        log_upgrade_result "PARTIAL"
    else
        log_upgrade_result "SUCCESS"
    fi
    
    # 输出完成信息
    echo ""
    log_info "=============================================="
    log_info "OTA 升级完成!"
    log_info "=============================================="
    log_info "从版本: $FROM_VERSION"
    log_info "到版本: $TO_VERSION"
    if [ -n "$BACKUP_DIR" ]; then
        log_info "备份位置: $BACKUP_DIR"
        log_info ""
        log_info "如需回滚，请运行:"
        log_info "  bash $0 --rollback $BACKUP_DIR"
    fi
    log_info "=============================================="
}

# 执行主函数
main "$@"

