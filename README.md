# 百度网盘自动备份与轮替脚本 (Baidu Netdisk Auto Backup & Rotation Script)

这是一个功能强大且稳定可靠的 Python 脚本，用于自动将服务器上的指定目录压缩，并以分片上传的方式备份到您的百度网盘个人空间。同时，它还支持自动删除旧备份，仅保留最新的 N 份，实现无人值守的备份周期管理。

This is a powerful and robust Python script that automatically compresses a specified local directory and uploads it to your Baidu Netdisk personal space using chunked uploading. It also supports automatic rotation by deleting old backups, keeping only the latest N copies for unattended backup cycle management.

---

## ✨ 主要功能 (Features)

- **📁 自动压缩**: 自动将指定的本地文件夹打包成带有时间戳的 `.tar.gz` 压缩文件。
- **🚀 大文件支持**: 通过分片上传机制，支持 TB 级别的超大文件备份，稳定可靠。
- **🔄 自动授权与刷新**: 首次运行仅需一次手动授权，后续脚本会自动管理并刷新 `access_token`，实现真正的无人值守。
- **♻️ 备份自动轮替**: 可自定义保留最新的备份数量，脚本会在每次成功上传后自动删除最旧的备份，有效管理网盘空间。
- **🔒 安全可靠**: 通过环境变量配置 `AppKey` 和 `SecretKey`，避免敏感信息硬编码在代码中泄露。
- **📊 可视化进度**: 使用 `tqdm` 库实时显示文件上传进度条，直观了解当前状态。
- **🔁 失败重试**: 内置简单的网络请求重试机制，从容应对临时的网络波动。
- **🧹 自动清理**: 无论任务成功或失败，都会自动删除本地产生的临时压缩文件，不占用服务器磁盘空间。
- **🕒 时间戳命名**: 备份文件会自动添加日期和时间戳（例如 `test_20250916-192645.tar.gz`），方便版本管理和追溯。

## ⚙️ 环境要求 (Prerequisites)

- Python 3.6+ (推荐 3.8 或更高版本)
- 百度网盘开放平台官方 Python SDK (`openapi_client` 目录)

## 📖 使用说明 (Usage)

请按照以下步骤来配置和运行此脚本。

### 第 1 步：成为百度网盘开放平台开发者

1.  访问 [百度网盘开放平台](https://pan.baidu.com/union/console) 并登录。
2.  完成个人或企业开发者实名认证。
3.  进入 **应用管理** -> **创建应用**，应用类型选择 **“个人应用-存储”**。
4.  创建成功后，在应用详情页可以找到您的 **`AppKey`** 和 **`SecretKey`**。

### 第 2 步：下载代码和 SDK

1.  克隆或下载本仓库到您的服务器。
2.  从百度网盘开放平台官网下载 [Python SDK]([https://pan.baidu.com/union/doc/al0a2g01s](https://pan.baidu.com/union/doc/Kl4gsu388))。
3.  解压SDK后，将名为 `openapi_client` 的整个文件夹**复制到**本脚本所在的同一目录下。

最终，您的项目目录结构应如下所示：

```
.
├── backup_script.py        # 您的Python脚本
├── openapi_client/         # 从官方SDK下载的文件夹
│   ├── api/
│   ├── model/
│   └── ...
└── README.md
```

### 第 3 步：安装依赖

在项目根目录下，使用 `pip` 安装所需的库：

```bash
pip install -r requirements.txt
```

### 第 4 步：配置脚本

1.  **修改脚本文件**:
    打开 `backup_script.py` (或者您自己的脚本文件名)，修改顶部的【配置区】：
    ```python
    # 1. 要备份的本地目录 (请使用绝对路径)
    LOCAL_DIR = "/path/to/your/data/to/backup"

    # 2. 要上传到的网盘目录 (必须以 /apps/ 开头，apps后面是你的应用名)
    REMOTE_DIR = "/apps/你的应用名称/backup_folder"
    
    # 3. 最大保留的备份文件数量 (设置为 0 则保留所有备份)
    MAX_BACKUPS = 7 # 例如，只保留最近7天的备份
    ```
2.  **设置环境变量 (重要)**:
    为了安全，请将 `AppKey` 和 `SecretKey` 设置为系统环境变量。

    **在 Linux / macOS 中:**
    ```bash
    export BAIDU_APP_KEY="你的AppKey"
    export BAIDU_SECRET_KEY="你的SecretKey"
    ```
    *为了永久生效，建议将这两行添加到 `~/.bashrc` 或 `~/.zshrc` 文件中，然后执行 `source ~/.bashrc`。*

    **在 Windows 中:**
    ```cmd
    set BAIDU_APP_KEY="你的AppKey"
    set BAIDU_SECRET_KEY="你的SecretKey"
    ```

### 第 5 步：运行脚本

1.  **首次运行 (授权)**:
    直接在终端中执行脚本：
    ```bash
    python3 backup_script.py
    ```
    程序会提示您在浏览器中打开一个URL。请复制该URL，在浏览器中登录并授权。授权成功后，将页面上显示的 `code` 码复制并粘贴到终端里，按回车。
    脚本会自动获取 `token` 并将其保存为 `baidu_token.json` 文件，然后开始执行备份任务。

2.  **后续运行**:
    再次运行脚本时，它会自动读取 `baidu_token.json` 文件，如果 `token` 过期会自动刷新，无需您再次手动授权。

### 第 6 步：设置定时任务 (例如：使用 Cron)

您可以设置一个 `cron` 定时任务来实现每日自动备份。例如，设置每天凌晨3点执行备份：

```bash
# 编辑 crontab
crontab -e

# 添加以下一行 (请确保使用脚本的绝对路径)
0 3 * * * /usr/bin/python3 /path/to/your/backup_script.py >> /path/to/your/backup.log 2>&1
```

## ⚠️ 注意事项

- **网盘路径**: 上传的目标路径 `REMOTE_DIR` 必须以 `/apps/` 开头，这是百度开放平台的规定。
- **网络问题**: 如果遇到 `SSLError` 或 `HTTPSConnectionPool` 相关的错误，这通常是您服务器的网络环境问题（例如防火墙、云服务商安全组策略），而不是脚本本身的问题。
- **API 限制**: 请遵守百度网盘开放平台的 API 调用频率限制。

## 📄 许可证 (License)

本项目采用 [MIT License](LICENSE) 授权。
