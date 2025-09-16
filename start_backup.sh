#!/bin/bash

# ==============================================================================
# ===== (✔) 最终高性能配置 - 所有配置项集中于此！ =====
# ==============================================================================

# --- 请在这里配置您的所有信息 ---
# 1. 百度开放平台凭证
export BAIDU_APP_KEY="你的AppKey"
export BAIDU_SECRET_KEY="你的SecretKey"

# 2. 本地备份源目录
LIVE_DATA_DIR="/opt"

# 3. 云端备份目标目录
REMOTE_DIR="/apps/你的应用名称/server_backups"

# 4. 最大保留的备份组数量 (设置为 0 则保留所有)
MAX_BACKUPS=7

# 5. 分卷大小
SPLIT_SIZE="1G"

# ==============================================================================
# ===== (🚀) 性能优化配置 =====
# ==============================================================================
# 6. 并行上传任务数
#    - 这个值决定了同时上传几个分卷。
#    - 建议从 2 或 3 开始尝试。如果您的服务器CPU和带宽都非常充裕，可以适当调高。
#    - 不建议超过您服务器的 CPU 核心数。
PARALLEL_UPLOADS=3
# ==============================================================================

# 7. Python 解释器和脚本的绝对路径
PYTHON_EXECUTABLE="/usr/bin/python3"
BACKUP_SCRIPT_PATH="/path/to/your/Baidu-Backup/Baidu-Backup.py"
# --- 配置结束 ---


# ==============================================================================
# ===== 主备份流程 (无需修改) =====
# ==============================================================================
echo "=========================================================="
echo "Baidu Backup Job (High-Performance Parallel Version) started at $(date)"
echo "=========================================================="

# 1. 准备目录和文件名
TIMESTAMP=$(date +'%Y%m%d-%H%M%S')
TAR_FILENAME_BASE="$(basename "$LIVE_DATA_DIR")_$TIMESTAMP.tar.gz"
SPLIT_DIR="$(dirname "$LIVE_DATA_DIR")/split_volumes_$TIMESTAMP"
mkdir -p "$SPLIT_DIR"

# 2. 使用管道进行流式压缩和分卷
echo "--> Step 1: Compressing and splitting on-the-fly..."
tar --ignore-failed-read -czf - -C "$(dirname "$LIVE_DATA_DIR")" "$(basename "$LIVE_DATA_DIR")" | split -b "$SPLIT_SIZE" -d - "$SPLIT_DIR/$TAR_FILENAME_BASE."

if [ -z "$(ls -A "$SPLIT_DIR")" ]; then
    echo "!! FATAL: Streaming process failed. No volumes were created. Aborting."
    rm -rf "$SPLIT_DIR"
    exit 1
fi
echo "--> Streaming process completed."

# ==============================================================================
# ===== 核心升级点：使用 xargs 进行并行上传 =====
# ==============================================================================
# 3. 并行上传每一个小分卷
echo "--> Step 2: Uploading volumes in parallel (max ${PARALLEL_UPLOADS} jobs)..."
# 创建一个临时日志文件来捕获所有并行任务的输出
LOG_FILE="${SPLIT_DIR}/parallel_upload.log"

# ls -1: 列出所有分卷文件名
# xargs -P: 指定最大并行进程数
# xargs -I {}: 将每个文件名赋值给占位符 {}
# bash -c '...': 启动一个独立的 shell 来执行我们的复杂命令
ls -1 "$SPLIT_DIR" | xargs -P "$PARALLEL_UPLOADS" -I {} bash -c \
"echo '--- Starting upload for {} ---' && \
cd '$(dirname "$BACKUP_SCRIPT_PATH")' && \
'$PYTHON_EXECUTABLE' '$BACKUP_SCRIPT_PATH' \
    --tar-path '$SPLIT_DIR/{}' \
    --remote-dir '$REMOTE_DIR' \
    --max-backups '$MAX_BACKUPS' && \
echo '--- Finished upload for {} ---'" >> "$LOG_FILE" 2>&1

# 检查临时日志中是否包含错误信息
if grep -q -e "❌" -e "ERROR" -e "FATAL" "$LOG_FILE"; then
    OVERALL_SUCCESS=false
else
    OVERALL_SUCCESS=true
fi
# 打印所有并行任务的日志
echo "--- Parallel Upload Log Start ---"
cat "$LOG_FILE"
echo "--- Parallel Upload Log End ---"
# ==============================================================================


# 4. 最终清理
echo "--> Step 3: Cleaning up..."
rm -rf "$SPLIT_DIR"
echo "--> Temporary split volumes deleted."

echo "=========================================================="
if [ "$OVERALL_SUCCESS" = true ]; then
    echo "Baidu Backup Job finished successfully at $(date)"
    exit 0
else
    echo "!! Baidu Backup Job finished with at least one ERROR at $(date)"
    exit 1
fi
