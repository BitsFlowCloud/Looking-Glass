# 1. 停止旧进程
pkill -f check_stream.py

# 2. 写入基于 curl 的高保真 Python 脚本
cat > /var/www/html/agent/check_stream.py << 'EOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import subprocess
import json
import argparse
import socket
import re
import sys

# ==========================================
# 配置与常量 (提取自 xykt/IPQuality)
# ==========================================
UA_BROWSER = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
TIMEOUT = "8"

# ==========================================
# 核心工具：Curl 包装器
# ==========================================
def run_curl(url, ip_version=4, method="GET", follow_redirects=True):
    """
    调用系统 curl 命令，模拟 Bash 脚本的行为
    """
    cmd = [
        "curl",
        "--max-time", TIMEOUT,
        "--user-agent", UA_BROWSER,
        "--silent",               # 静默模式
        "--write-out", "%{http_code}", # 最后输出状态码
    ]

    # IP 版本强制
    if ip_version == 6:
        cmd.append("-6")
    else:
        cmd.append("-4")

    # 是否跟随跳转
    if follow_redirects:
        cmd.append("-L")
    else:
        # 如果不跟随跳转，我们需要 Header 来分析 Location
        cmd.append("-I") 

    # URL
    cmd.append(url)

    try:
        # 执行命令
        result = subprocess.run(cmd, capture_output=True, text=True)
        
        # 解析结果
        # stdout 包含页面内容(如果有) + 最后的 http_code
        output = result.stdout
        http_code = 0
        body = ""
        
        if output:
            try:
                # 提取最后3位作为状态码
                http_code = int(output[-3:])
                body = output[:-3] # 剩下的就是 body 或 headers
            except:
                pass
                
        return {
            "code": http_code,
            "body": body,
            "error": False
        }
    except Exception as e:
        return {"code": 0, "body": "", "error": True}

def is_ipv6_supported():
    """检测 IPv6 连通性"""
    try:
        sock = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
        sock.settimeout(2)
        sock.connect(('2001:4860:4860::8888', 53))
        sock.close()
        return True
    except:
        return False

# ==========================================
# 提取自 xykt/IPQuality 的检测逻辑
# ==========================================

def check_netflix(ver):
    """
    标准脚本逻辑：
    访问 Breaking Bad (81280792)
    - 404: 无法观看
    - 403: 封锁
    - 200: 正常
    - 301/302: 获取 Location 判断地区
    """
    # 1. 检查自制剧 (House of Cards) - 基础解锁
    res_org = run_curl("https://www.netflix.com/title/80018499", ver, follow_redirects=True)
    if res_org['code'] != 200:
        return "No"

    # 2. 检查非自制 (Breaking Bad) - 完整解锁
    # 这里使用不跟随跳转 (-I) 来获取 Location，这是 Bash 脚本常用的判断地区方法
    res = run_curl("https://www.netflix.com/title/81280792", ver, follow_redirects=False)
    
    if res['code'] == 403:
        return "No"
    
    if res['code'] == 200:
        # 页面直接返回 200，说明没有跳转，通常是 US 或者当前 IP 所在区
        return "Yes (Region: US)"
    
    if res['code'] in [301, 302]:
        # 提取 Location
        # curl -I 的输出在 body 里
        match = re.search(r'[lL]ocation:\s*https?://www\.netflix\.com/([a-z]{2}-[a-z]{2})/', res['body'])
        if match:
            region = match.group(1).split('-')[0].upper()
            return f"Yes (Region: {region})"
        
        # 备用正则
        match2 = re.search(r'[lL]ocation:\s*/([a-z]{2})/', res['body'])
        if match2:
            region = match2.group(1).upper()
            return f"Yes (Region: {region})"

    # 如果非自制剧挂了，但自制剧通过了
    return "Yes (Originals Only)"

def check_youtube(ver, region_code):
    """
    标准脚本逻辑：
    访问 /premium，查找 "Premium" 关键词
    """
    res = run_curl("https://www.youtube.com/premium", ver, follow_redirects=True)
    
    if res['code'] != 200:
        return "Network Error"
    
    is_premium = "No"
    if "United States" in res['body'] or "YouTube Premium" in res['body'] or "try free" in res['body'].lower():
        is_premium = "Yes"
    
    # 地区修正
    region = region_code if region_code != "Unknown" else "Global"
    
    # 尝试从 Youtube 源码获取 countryCode
    match = re.search(r'"countryCode":"([A-Z]{2})"', res['body'])
    if match:
        region = match.group(1)

    return f"Region: {region} | Premium: {is_premium}"

def check_disney(ver):
    """
    标准脚本逻辑：
    访问主页，403/0 为失败，200 为成功。
    """
    res = run_curl("https://www.disneyplus.com/", ver, follow_redirects=True)
    
    if res['code'] == 0: return "Network Error"
    if res['code'] == 403: return "No"
    
    if res['code'] == 200:
        # 检查是否跳转到了 preview (未服务区)
        if "preview" in res['body'] or "unavailable" in res['body']:
             return "No (Region Unavailable)"
        
        # 尝试解析地区 (从 URL 或 meta 标签，这里简化处理，Curl 拿 URL 比较麻烦，除非解析 -L 后的最终 URL)
        # 简单返回 Yes
        return "Yes"
        
    return "No"

def check_tiktok(ver):
    res = run_curl("https://www.tiktok.com/", ver, follow_redirects=True)
    if res['code'] == 200: return "Yes"
    return "No"

def check_gemini(ver):
    res = run_curl("https://gemini.google.com", ver, follow_redirects=True)
    if res['code'] == 200 and ("Google" in res['body'] or "Sign in" in res['body']):
        return "Yes"
    return "No"

# ==========================================
# 主程序
# ==========================================

def run_suite(ver, name):
    print(f"--- Checking via {name} ---")
    
    # 获取 IP 归属地 (用于辅助判断)
    region_code = "Unknown"
    try:
        # 使用 curl 获取 ip info，避免 python 库差异
        cmd = ["curl", "-s", "--max-time", "4", "http://ip-api.com/json/"]
        if ver == 6: cmd.append("-6")
        else: cmd.append("-4")
        
        out = subprocess.run(cmd, capture_output=True, text=True).stdout
        data = json.loads(out)
        region_code = data.get('countryCode', 'Unknown')
        print(f"IP Info: [{region_code}] {data.get('isp', '')}")
    except:
        print("IP Info: Unknown")

    results = {
        'netflix': check_netflix(ver),
        'youtube': check_youtube(ver, region_code),
        'disney': check_disney(ver),
        'tiktok': check_tiktok(ver),
        'gemini': check_gemini(ver),
        'spotify': 'N/A' # Curl 模拟 Spotify 登录极其复杂，暂跳过
    }
    
    for k, v in results.items():
        print(f"{k.capitalize()}: {v}")
        
    return results

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=str, help="Output JSON result to file")
    args = parser.parse_args()

    final_data = {}
    
    # IPv4
    final_data['v4'] = run_suite(4, "IPv4")
    print("\n")

    # IPv6
    if is_ipv6_supported():
        final_data['v6'] = run_suite(6, "IPv6")
    else:
        print("--- Checking via IPv6 ---")
        print("IPv6 Unavailable (Skipping checks)")
        final_data['v6'] = { k: 'N/A' for k in final_data['v4'].keys() }

    # Output
    if args.out:
        with open(args.out, 'w') as f:
            json.dump(final_data, f)
        try:
            import os
            os.chmod(args.out, 0o644)
            os.chown(args.out, 33, 33) 
        except: pass
        print(f"\nSaved result to {args.out}")
    else:
        print(json.dumps(final_data, indent=4))

if __name__ == "__main__":
    main()
EOF

# 3. 修复权限
chown www-data:www-data /var/www/html/agent/check_stream.py
chmod +x /var/www/html/agent/check_stream.py

# 4. 手动运行测试
echo ">>> 正在使用 Curl 核心运行检测..."
su -s /bin/bash -c "python3 /var/www/html/agent/check_stream.py --out /var/www/html/agent/unlock_result.json" www-data

echo ">>> 完成！此版本调用系统 Curl，结果应与 Bash 脚本一致。"
