# Baidu-Backup：高性能百度网盘自动备份与轮替解决方案

**Baidu-Backup** 是一个功能强大、经过实战考验的自动化备份解决方案。它通过一个高度优化的 `Shell` 脚本和 `Python` 引擎协同工作，将您的服务器数据以**高性能并行**的方式，自动备份到百度网盘，并智能地管理历史备份，实现真正的“一劳永逸”。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

---

## 🚀 为什么选择 Baidu-Backup？

我们不仅仅是一个上传脚本，我们是一个**完整的、生产级别的自动化运维解决方案**，专为解决真实世界中的复杂问题而设计：

-   **极致性能，并行上传**: 独创的**并行上传**机制，将大文件切割成多个分卷后同时上传，能榨干您的服务器带宽，将备份时间**成倍缩短**。
-   **流式处理，零硬盘占用**: 采用 `tar` 和 `split` 的**管道流式处理**技术，在压缩和分卷的过程中，**完全不产生巨大的中间文件**，对硬盘空间极其友好。
-   **智能轮替，空间无忧**: 可自定义保留最新的备份“组”（一个完整备份的所有分卷）。脚本会在每次成功上传后，自动删除最旧的备份组，实现完美的备份周期管理。
-   **无人值守，长达十年**: 仅需一次手动授权，脚本即可在长达 **10 年**内自动刷新 `Token`，无需任何人工干预。
-   **数据校验，确保可靠**: Python 引擎内置**双重 MD5 文件完整性自检**，并在上传后由百度服务器进行最终校验，确保您备份的每一个字节都准确无误。
-   **清晰架构，易于配置**: 采用**配置与引擎分离**的专业架构。您只需要修改 `start_backup.sh` 这一个文件，即可完成所有配置，Python 脚本无需任何改动。
-   **高容错性**: 针对备份“动态目录”（如运行中的网站或游戏服务器）的场景，脚本内置了多种容错机制，确保在源文件频繁变化时，依然能最大限度地成功创建备份。
-   **日志清晰，易于排错**: 专为自动化任务设计的日志系统，在并行模式下也能保持清晰可读。若无事，则静默；若有错，则详尽。

## ⚙️ 架构简介

Baidu-Backup 由两个核心组件构成，各司其职：

1.  **`start_backup.sh` (总指挥 & 配置文件)**
    -   **职责**: 负责所有**本地操作**和**参数配置**。
    -   **工作流**: 流式压缩 -> 动态分卷 -> **并行调度** Python 引擎。
    -   **您需要修改的唯一文件！**

2.  **`111.py` (上传引擎)**
    -   **职责**: 负责所有**云端操作**。
    -   **工作流**: 接收 Shell 脚本传递的参数 -> 本地文件自检 -> 上传分卷 -> 智能轮替云端备份。
    -   **一个完全无需修改的“黑盒工具”。**

## 📖 快速上手指南

### 第 1 步：获取百度开放平台凭证

1.  访问 [百度网盘开放平台](https://pan.baidu.com/union/console) 并登录。
2.  完成开发者认证，然后创建一个“个人应用-存储”类型的应用。
3.  在应用详情页，记下您的 **`AppKey`** 和 **`SecretKey`**。

### 第 2 步：部署项目

1.  克隆本仓库到您的服务器：
    ```bash
    git clone https://github.com/lansepeach/Baidu-Backup.git
    cd Baidu-Backup
    ```
2.  从官网下载 [Python SDK](https://pan.baidu.com/union/doc/Kl4gsu388)，解压后将 `openapi_client` 文件夹整个复制到 `Baidu-Backup` 项目目录下。
3.  安装依赖：
    ```bash
    pip3 install requests
    ```

### 第 3 步：配置 `start_backup.sh`

打开 `start_backup.sh` 文件，这是您唯一需要修改的文件。请根据注释，填写您的信息。

```bash
#!/bin/bash

# --- 请在这里配置您的所有信息 ---
# 1. 百度开放平台凭证
export BAIDU_APP_KEY="你的AppKey"
export BAIDU_SECRET_KEY="你的SecretKey"

# 2. 本地备份源目录
LIVE_DATA_DIR="/path/to/your/data/to/backup"

# 3. 云端备份目标目录
REMOTE_DIR="/apps/你的应用名称/server_backups"

# 4. 最大保留的备份组数量 (设置为 0 则保留所有)
MAX_BACKUPS=7 # 例如，只保留最近7天的备份

# 5. 分卷大小 (1G 是一个非常推荐的稳健值)
SPLIT_SIZE="1G"

# 6. (🚀) 并行上传任务数 (建议从 2 或 3 开始)
PARALLEL_UPLOADS=3

# 7. Python 解释器和脚本的绝对路径 (请确认为您服务器上的真实路径)
PYTHON_EXECUTABLE="/usr/bin/python3"
BACKUP_SCRIPT_PATH="/path/to/your/Baidu-Backup/Baidu-Backup.py"
# --- 配置结束 ---
```

### 第 4 步：授权与运行

1.  **授予执行权限**:
    ```bash
    chmod +x start_backup.sh
    ```

2.  **首次运行 (交互式授权)**:
    直接在终端中执行：
    ```bash
    ./start_backup.sh
    ```
    脚本会检测到 `baidu_token.json` 文件不存在，并自动进入授权流程。请根据 Python 脚本的提示，在浏览器中打开 URL，完成授权，然后将 `code` 码粘贴回终端。
    
    授权成功后，备份任务将自动开始。

3.  **后续运行 (全自动)**:
    再次运行 `./start_backup.sh` 时，脚本将全自动静默运行，无需任何交互。

### 第 5 步：设置定时任务 (Cron Job)

将您的备份任务自动化，例如，设置每天凌晨3点执行：

```bash
# 编辑 crontab
crontab -e

# 添加以下一行 (请确保使用 start_backup.sh 的绝对路径)
0 3 * * * /path/to/your/Baidu-Backup/start_backup.sh >> /var/log/baidu_backup.log 2>&1
```

## 恢复备份

1.  将属于同一个备份批次的所有分卷文件（例如 `..._20250917-030000.tar.gz.00`, `...01`, `...02`）下载到同一个目录。
2.  使用 `cat` 命令将它们合并成一个完整的压缩包：
    ```bash
    cat your_backup_timestamp.tar.gz.* > complete_backup.tar.gz
    ```
3.  解压即可：
    ```bash
    tar -xzf complete_backup.tar.gz
    ```

## 🤝 贡献

如果您有任何问题或改进建议，欢迎提交 [Issues](https://github.com/lansepeach/Baidu-Backup/issues) 或 Pull Requests。如果这个项目对您有帮助，请不要吝啬您的 **Star** ⭐！

## 📄 许可证

本项目采用 [MIT License](LICENSE) 授权。
