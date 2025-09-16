#!/usr/bin/env python3
import os
import json
import hashlib
import tarfile
import time
import requests
import io
from tqdm import tqdm
from openapi_client.api import fileupload_api
from openapi_client import ApiClient, ApiException

# ==============================================================================
# ===== 配置区 (您只需要修改这里) =====
# ==============================================================================

# 1. 要备份的本地目录 (请使用绝对路径)
LOCAL_DIR = "/opt"

# 2. 要上传到的网盘目录 (必须以 /apps/ 开头)
REMOTE_DIR = "/apps/应用名称/目录名称"

# ==============================================================================
# ===== 程序核心代码 (以下部分无需修改) =====
# ==============================================================================

# --- 从环境变量安全地读取密钥 ---
APP_KEY = os.getenv("BAIDU_APP_KEY")
SECRET_KEY = os.getenv("BAIDU_SECRET_KEY")

# --- 全局常量 ---
REDIRECT_URI = "oob"
TOKEN_FILE = "baidu_token.json"
CHUNK_SIZE = 4 * 1024 * 1024 # 使用4MB分片以提高效率

# ===== Token 管理 =====
def get_access_token():
    """获取或刷新有效的 access_token"""
    if not all([APP_KEY, SECRET_KEY]):
        print("❌ 错误：请先设置系统环境变量 BAIDU_APP_KEY 和 BAIDU_SECRET_KEY")
        exit(1)

    if os.path.exists(TOKEN_FILE):
        try:
            with open(TOKEN_FILE, "r") as f:
                token_data = json.load(f)
            if time.time() < token_data["expires_at"]:
                print("✅ 使用本地 access_token")
                return token_data["access_token"]
            else:
                print("🔄 access_token 已过期，尝试刷新...")
                refresh_token = token_data.get("refresh_token")
                if refresh_token:
                    return refresh_access_token(refresh_token)
        except (json.JSONDecodeError, KeyError):
            print("⚠️ Token 文件格式错误，将重新授权。")
            
    return authorize_new_token()

def authorize_new_token():
    """引导用户完成首次授权流程"""
    auth_url = (
        f"https://openapi.baidu.com/oauth/2.0/authorize"
        f"?response_type=code&client_id={APP_KEY}"
        f"&redirect_uri={REDIRECT_URI}&scope=basic,netdisk"
    )
    print("\n首次运行或授权失败，请在浏览器打开以下链接，登录并授权：\n")
    print(auth_url)
    code = input("\n请输入浏览器返回的 code: ").strip()

    token_url = "https://openapi.baidu.com/oauth/2.0/token"
    params = {
        "grant_type": "authorization_code", "code": code,
        "client_id": APP_KEY, "client_secret": SECRET_KEY,
        "redirect_uri": REDIRECT_URI
    }
    resp = requests.get(token_url, params=params)
    resp.raise_for_status()
    data = resp.json()

    if "access_token" in data:
        save_token(data)
        return data["access_token"]
    else:
        raise RuntimeError(f"获取 access_token 失败: {data}")

def refresh_access_token(refresh_token):
    """使用 refresh_token 刷新 access_token"""
    token_url = "https://openapi.baidu.com/oauth/2.0/token"
    params = {
        "grant_type": "refresh_token", "refresh_token": refresh_token,
        "client_id": APP_KEY, "client_secret": SECRET_KEY
    }
    resp = requests.get(token_url, params=params)
    resp.raise_for_status()
    data = resp.json()

    if "access_token" in data:
        save_token(data)
        return data["access_token"]
    else:
        print("❌ 刷新 token 失败，需要重新授权")
        return authorize_new_token()

def save_token(data):
    """将 token 数据保存到本地文件"""
    data["expires_at"] = time.time() + int(data["expires_in"]) - 300 # 提前5分钟过期
    with open(TOKEN_FILE, "w") as f:
        json.dump(data, f, indent=4)
    print("💾 已保存新的 token")

# ===== 上传工具 =====
def md5_bytes(data):
    """计算二进制数据的MD5值"""
    return hashlib.md5(data).hexdigest()

def get_block_md5_list(path):
    """计算文件的分片MD5列表"""
    block_md5_list = []
    with open(path, "rb") as f:
        while True:
            chunk = f.read(CHUNK_SIZE)
            if not chunk:
                break
            block_md5_list.append(md5_bytes(chunk))
    return block_md5_list

def upload_part(api_instance, access_token, remote_path, uploadid, part_index, local_path):
    """上传单个文件分片（已解决SDK兼容性问题）"""
    for attempt in range(3):
        try:
            with open(local_path, "rb") as fp:
                # ==============================================================================
                # ===== 错误修正点 (CHK_SIZE -> CHUNK_SIZE) =====
                # ==============================================================================
                fp.seek(part_index * CHUNK_SIZE)
                chunk_data = fp.read(CHUNK_SIZE)
                if not chunk_data: break
                
                # 核心修正：使用 io.BytesIO 并动态添加 .name 属性，以满足SDK的两个苛刻要求
                with io.BytesIO(chunk_data) as chunk_fp:
                    chunk_fp.name = 'chunk_part_data'
                    
                    api_instance.pcssuperfile2(
                        access_token=access_token, partseq=str(part_index),
                        path=remote_path, uploadid=uploadid, type="tmpfile",
                        file=chunk_fp, _request_timeout=300
                    )
            return # 上传成功，退出函数
        except ApiException as e:
            if 400 <= e.status < 500:
                raise RuntimeError(f"分片 {part_index} 上传失败 (客户端错误 {e.status})，中止上传: {e.reason}")
            print(f"⚠️ 分片 {part_index} 上传失败 (API错误)，第 {attempt+1} 次重试: {e.reason}")
            time.sleep(2 ** attempt)
        except Exception as e:
            print(f"⚠️ 分片 {part_index} 上传失败 (网络或其他错误)，第 {attempt+1} 次重试: {e}")
            time.sleep(2 ** attempt)
            
    raise RuntimeError(f"❌ 分片 {part_index} 上传失败，已重试 3 次")

def upload_large_file(api_instance, access_token, local_path, remote_path):
    """完整的大文件上传流程：预上传 -> 分片上传 -> 合并"""
    file_size = os.path.getsize(local_path)
    print(f"文件大小: {file_size / 1024 / 1024:.2f} MB")
    
    # 1. 预上传
    print("⏳ 正在进行预上传...")
    block_md5_list = get_block_md5_list(local_path)
    precreate_resp = api_instance.xpanfileprecreate(
        access_token=access_token, path=remote_path, size=file_size,
        isdir=0, autoinit=1, block_list=json.dumps(block_md5_list)
    )
    uploadid = precreate_resp.get("uploadid")
    if not uploadid:
        raise RuntimeError(f"预上传失败: {precreate_resp}")
    print(f"✅ 预上传成功, UploadID: {uploadid}")

    # 2. 分片上传
    print("🚀 开始分片上传...")
    with tqdm(total=len(block_md5_list), unit="part", desc="上传进度") as pbar:
        for idx in range(len(block_md5_list)):
            upload_part(api_instance, access_token, remote_path, uploadid, idx, local_path)
            pbar.update(1)

    # 3. 合并文件
    print("🤝 正在合并文件...")
    create_resp = api_instance.xpanfilecreate(
        access_token=access_token, path=remote_path, size=file_size,
        isdir=0, uploadid=uploadid, block_list=json.dumps(block_md5_list)
    )
    if 'fs_id' not in create_resp:
         raise RuntimeError(f"合并文件失败: {create_resp}")
    print(f"🎉 文件上传成功! 网盘路径: {create_resp.get('path')}")

def compress_directory(local_dir, output_path):
    """将目录压缩成 .tar.gz 文件"""
    print(f"📦 正在压缩 {local_dir} -> {output_path}")
    with tarfile.open(output_path, "w:gz") as tar:
        tar.add(local_dir, arcname=os.path.basename(local_dir))
    print("压缩完成")

# ===== 主流程 =====
if __name__ == "__main__":
    if not os.path.isdir(LOCAL_DIR):
        print(f"❌ 错误: 本地目录 '{LOCAL_DIR}' 不存在或不是一个目录。")
        exit(1)
        
    # 动态生成压缩文件名
    tar_filename = f"{os.path.basename(LOCAL_DIR.rstrip(os.sep))}_{time.strftime('%Y%m%d-%H%M%S')}.tar.gz"
    # 将临时压缩文件放在 LOCAL_DIR 的父目录下
    local_tar_path = os.path.join(os.path.dirname(LOCAL_DIR.rstrip(os.sep)), tar_filename)

    try:
        access_token = get_access_token()
        compress_directory(LOCAL_DIR, local_tar_path)
        
        with ApiClient() as api_client:
            api_instance = fileupload_api.FileuploadApi(api_client)
            remote_tar_path = os.path.join(REMOTE_DIR, os.path.basename(local_tar_path)).replace("\\", "/")
            upload_large_file(api_instance, access_token, local_tar_path, remote_tar_path)

    except Exception as e:
        print(f"\n❌ 执行过程中发生严重错误: {e}")
    finally:
        if 'local_tar_path' in locals() and os.path.exists(local_tar_path):
            print(f"🗑️ 删除本地临时压缩文件: {local_tar_path}")
            os.remove(local_tar_path)
