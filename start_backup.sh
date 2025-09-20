#!/bin/bash

# ==============================================================================
# 新增：检查必要工具是否安装
# ==============================================================================
check_dependencies() {
    local dependencies=("bc" "tar" "split" "curl" "python3")
    local missing=()
    
    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo "❌ 缺少必要工具，请先安装："
        for dep in "${missing[@]}"; do
            echo "   - $dep"
        done
        exit 1
    fi
}

# 执行依赖检查
check_dependencies

# 保持原有bash脚本内容不变
# 所有配置和流程与之前一致，无需修改
# ==============================================================================
# ===== (✔) 最终高性能配置 - 所有配置项集中于此！ =====
# ==============================================================================

# --- 请在这里配置您的所有信息 ---
# 1. 百度开放平台凭证
export BAIDU_APP_KEY="你的AppKey"
export BAIDU_SECRET_KEY="你的SecretKey"

# 2. 本地备份源目录
LIVE_DATA_DIR="/www/wwwroot/要备份的目录"

# 3. 云端备份目标目录
REMOTE_DIR="/apps/测试百度备份/server_backups"

# 4. 最大保留的备份组数量 (设置为 0 则保留所有)
MAX_BACKUPS=10

# 5. 分卷大小（仅当文件超过此大小时才分卷）
SPLIT_SIZE="1G"

# ==============================================================================
# ===== (🚀) 性能优化配置 =====
# ==============================================================================
# 6. 并行上传任务数
PARALLEL_UPLOADS=3
# ==============================================================================

# 7. Python 解释器和脚本的绝对路径
PYTHON_EXECUTABLE="/usr/bin/python3"
BACKUP_SCRIPT_PATH="/www/wwwroot/项目目录/Baidu-Backup/Baidu-Backup.py"
# 认证信息缓存文件
TOKEN_CACHE_FILE="$HOME/.baidu_backup_token"
# --- 配置结束 ---


# ==============================================================================
# ===== 处理百度云授权流程 =====
# ==============================================================================
handle_authorization() {
    # 检查是否已有有效令牌缓存
    if [ -f "$TOKEN_CACHE_FILE" ]; then
        echo "--> 发现缓存的授权信息，尝试使用..."
        export BAIDU_ACCESS_TOKEN=$(cat "$TOKEN_CACHE_FILE")
        return 0
    fi

    # 执行授权流程
    echo "--> 需要百度云授权访问"
    AUTH_URL="https://openapi.baidu.com/oauth/2.0/authorize?response_type=code&client_id=$BAIDU_APP_KEY&redirect_uri=oob&scope=basic,netdisk"
    
    echo "请在浏览器打开以下链接，登录并授权："
    echo
    echo "$AUTH_URL"
    echo
    
    # 交互式获取授权码
    read -p "请输入浏览器返回的授权码: " AUTH_CODE
    
    # 验证用户输入
    if [ -z "$AUTH_CODE" ]; then
        echo "❌ 错误：授权码不能为空"
        return 1
    fi

    # 使用curl直接获取访问令牌
    echo "--> 验证授权码并获取访问令牌..."
    RESPONSE=$(curl -s "https://openapi.baidu.com/oauth/2.0/token?grant_type=authorization_code&code=$AUTH_CODE&client_id=$BAIDU_APP_KEY&client_secret=$BAIDU_SECRET_KEY&redirect_uri=oob")
    
    # 解析返回的JSON获取访问令牌
    ACCESS_TOKEN=$(echo "$RESPONSE" | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
    
    if [ -z "$ACCESS_TOKEN" ]; then
        echo "❌ 错误：获取访问令牌失败"
        echo "服务器返回：$RESPONSE"
        return 1
    fi

    # 保存令牌供后续使用
    echo "$ACCESS_TOKEN" > "$TOKEN_CACHE_FILE"
    export BAIDU_ACCESS_TOKEN="$ACCESS_TOKEN"
    echo "--> 授权成功，令牌已保存"
    return 0
}


# ==============================================================================
# ===== 主备份流程 =====
# ==============================================================================
echo "=========================================================="
echo "Baidu Backup Job (High-Performance Parallel Version) started at $(date)"
echo "=========================================================="

# 0. 先处理授权
echo "--> Step 0: 处理百度云授权..."
if ! handle_authorization; then
    echo "!! 授权失败，无法继续备份流程"
    exit 1
fi

# 1. 准备目录和文件名
TIMESTAMP=$(date +'%Y%m%d-%H%M%S')
TAR_FILENAME_BASE="$(basename "$LIVE_DATA_DIR")_$TIMESTAMP.tar.gz"
SPLIT_DIR="$(dirname "$LIVE_DATA_DIR")/split_volumes_$TIMESTAMP"
mkdir -p "$SPLIT_DIR"
TEMP_TAR_FILE="$SPLIT_DIR/$TAR_FILENAME_BASE"

# 2. 压缩并根据大小决定是否分卷
echo "--> Step 1: Compressing and conditionally splitting..."
# 先压缩到临时文件
tar --ignore-failed-read -czf "$TEMP_TAR_FILE" -C "$(dirname "$LIVE_DATA_DIR")" "$(basename "$LIVE_DATA_DIR")"

# 检查文件大小是否超过设定的分卷大小
# 将SPLIT_SIZE转换为字节以便比较
case $SPLIT_SIZE in
    *G) SIZE_BYTES=$(echo "${SPLIT_SIZE%G} * 1024 * 1024 * 1024" | bc) ;;
    *M) SIZE_BYTES=$(echo "${SPLIT_SIZE%M} * 1024 * 1024" | bc) ;;
    *K) SIZE_BYTES=$(echo "${SPLIT_SIZE%K} * 1024" | bc) ;;
    *) SIZE_BYTES=$SPLIT_SIZE ;;
esac

# 获取实际文件大小（字节）
FILE_SIZE=$(stat -c%s "$TEMP_TAR_FILE")

# 如果文件大小超过设定值则分卷，否则保持原文件
if [ $FILE_SIZE -gt $SIZE_BYTES ]; then
    echo "--> 文件大小超过$SPLIT_SIZE，进行分卷处理..."
    split -b "$SPLIT_SIZE" -d "$TEMP_TAR_FILE" "$TEMP_TAR_FILE."
    rm "$TEMP_TAR_FILE"  # 删除未分卷的原始文件
else
    echo "--> 文件大小小于$SPLIT_SIZE，无需分卷..."
fi

if [ -z "$(ls -A "$SPLIT_DIR")" ]; then
    echo "!! FATAL: 压缩过程失败，未生成任何文件。终止备份。"
    rm -rf "$SPLIT_DIR"
    exit 1
fi
echo "--> 压缩过程完成。"

# 3. 并行上传文件
echo "--> Step 2: 并行上传文件 (最多 ${PARALLEL_UPLOADS} 个任务)..."
LOG_FILE="${SPLIT_DIR}/parallel_upload.log"

# 上传文件（分卷或单个文件）
ls -1 "$SPLIT_DIR" | xargs -P "$PARALLEL_UPLOADS" -I {} bash -c \
"export BAIDU_ACCESS_TOKEN='$BAIDU_ACCESS_TOKEN' && \
echo '--- 开始上传 {} ---' && \
cd '$(dirname "$BACKUP_SCRIPT_PATH")' && \
'$PYTHON_EXECUTABLE' '$BACKUP_SCRIPT_PATH' \
    --tar-path '$SPLIT_DIR/{}' \
    --remote-dir '$REMOTE_DIR' \
    --max-backups '$MAX_BACKUPS' && \
echo '--- 完成上传 {} ---'" >> "$LOG_FILE" 2>&1

# 检查上传日志
if grep -q -e "❌" -e "ERROR" -e "FATAL" "$LOG_FILE"; then
    OVERALL_SUCCESS=false
else
    OVERALL_SUCCESS=true
fi
echo "--- 并行上传日志开始 ---"
cat "$LOG_FILE"
echo "--- 并行上传日志结束 ---"

# 4. 最终清理
echo "--> Step 3: 清理临时文件..."
rm -rf "$SPLIT_DIR"
echo "--> 临时文件已删除。"

echo "=========================================================="
if [ "$OVERALL_SUCCESS" = true ]; then
    echo "百度云备份任务成功完成于 $(date)"
    exit 0
else
    echo "!! 百度云备份任务完成时有错误发生于 $(date)"
    exit 1
fi
