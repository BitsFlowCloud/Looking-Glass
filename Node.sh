#!/bin/bash

# 定义颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# ==========================================
# 默认配置
# ==========================================
DEFAULT_WEB_ROOT="/root/www/wwwroot/lg-node"
DEFAULT_PORT=8080
PID_FILE="/tmp/lg-node.pid"
LOG_FILE="/tmp/lg-node.log"

echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}   BitsFlowCloud Looking Glass - 节点端部署   ${NC}"
echo -e "${GREEN}=============================================${NC}"

# ==========================================
# 0. 环境与依赖检查 (Pre-flight Check)
# ==========================================
function check_env() {
    echo -e "${YELLOW}正在检查系统环境...${NC}"

    # 1. 检查 Root 权限
    if [[ $EUID -ne 0 ]]; then
       echo -e "${RED}错误: 请使用 root 用户运行此脚本。${NC}"
       exit 1
    fi

    # 2. 检查并安装系统工具
    # 需要: python3, pip, iperf3, mtr, curl, traceroute, php-cli (用于跑 agent.php)
    PACKAGES="python3 python3-pip iperf3 mtr curl traceroute php-cli"
    MISSING_PACKAGES=""

    for pkg in $PACKAGES; do
        if ! command -v $pkg &> /dev/null; then
            # 特殊处理: pip 可能叫 pip3, php-cli 可能叫 php
            if [[ "$pkg" == "python3-pip" ]] && command -v pip3 &>/dev/null; then continue; fi
            if [[ "$pkg" == "php-cli" ]] && command -v php &>/dev/null; then continue; fi
            MISSING_PACKAGES="$MISSING_PACKAGES $pkg"
        fi
    done

    if [ -n "$MISSING_PACKAGES" ]; then
        echo -e "${YELLOW}发现缺失依赖: $MISSING_PACKAGES，正在安装...${NC}"
        if [ -f /etc/debian_version ]; then
            apt-get update
            apt-get install -y python3 python3-pip iperf3 mtr curl traceroute php-cli
        elif [ -f /etc/redhat-release ]; then
            yum install -y python3 python3-pip iperf3 mtr curl traceroute php-cli
        else
            echo -e "${RED}无法识别的操作系统，请手动安装: $PACKAGES${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}[OK] 系统工具已安装${NC}"
    fi

    # 3. 检查 Python 库 (requests)
    if ! python3 -c "import requests" &> /dev/null; then
        echo -e "${YELLOW}正在安装 Python requests 库...${NC}"
        pip3 install requests
    else
        echo -e "${GREEN}[OK] Python requests 库已安装${NC}"
    fi
}

# ==========================================
# 1. 交互式配置向导
# ==========================================
function configure_node() {
    echo -e "${YELLOW}>>> 进入配置向导${NC}"

    # 1. 安装目录
    read -p "1. 安装目录 [$DEFAULT_WEB_ROOT]: " INPUT_DIR
    WEB_ROOT=${INPUT_DIR:-$DEFAULT_WEB_ROOT}

    # 2. IP 地址确认
    echo -e "   正在检测 IP 地址..."
    AUTO_V4=$(curl -s4 ip.sb --max-time 3 || echo "")
    AUTO_V6=$(curl -s6 ip.sb --max-time 3 || echo "")
    
    echo -e "   检测到 IPv4: ${GREEN}${AUTO_V4:-未检测到}${NC}"
    echo -e "   检测到 IPv6: ${GREEN}${AUTO_V6:-未检测到}${NC}"
    
    read -p "2. 确认 IPv4 地址 (回车使用检测值): " INPUT_V4
    IPV4=${INPUT_V4:-$AUTO_V4}
    
    read -p "3. 确认 IPv6 地址 (回车使用检测值): " INPUT_V6
    IPV6=${INPUT_V6:-$AUTO_V6}

    # 3. 通信密钥 (强制)
    while true; do
        echo -e "   (此密钥需与主控端 config.php 中的 key 保持一致)"
        read -p "4. 请设置通信密钥 (Secret Key): " SECRET_KEY
        if [ -n "$SECRET_KEY" ]; then break; fi
        echo -e "${RED}密钥不能为空！${NC}"
    done

    # 4. 运行端口
    read -p "5. 节点服务端口 (用于内置 Web Server) [$DEFAULT_PORT]: " INPUT_PORT
    NODE_PORT=${INPUT_PORT:-$DEFAULT_PORT}

    echo -e "${GREEN}配置已就绪！${NC}"
}

# ==========================================
# 2. 部署核心文件
# ==========================================
function install_files() {
    # 如果未配置，先运行配置
    if [ -z "$WEB_ROOT" ]; then configure_node; fi
    
    if [ ! -d "$WEB_ROOT" ]; then
        echo -e "${YELLOW}目录不存在，正在创建: $WEB_ROOT${NC}"
        mkdir -p "$WEB_ROOT"
    fi

    echo -e "${YELLOW}正在生成 agent.php...${NC}"

    # --- 生成 agent.php ---
    cat << EOF > "$WEB_ROOT/agent.php"
<?php
error_reporting(0);
header('Content-Type: text/plain; charset=utf-8');
header('Access-Control-Allow-Origin: *');

\$SECRET_KEY   = '$SECRET_KEY'; 
\$PUBLIC_IP_V4 = '$IPV4'; 
\$PUBLIC_IP_V6 = '$IPV6'; 

if ((\$_POST['key'] ?? '') !== \$SECRET_KEY) {
    http_response_code(403);
    exit("Auth Failed");
}

\$action = \$_POST['action'] ?? '';
\$tool   = \$_POST['tool'] ?? '';
\$target = \$_POST['target'] ?? '';
\$proto  = \$_POST['proto'] ?? 'IPv4';

function get_cmd(\$names) {
    \$list = is_array(\$names) ? \$names : [\$names];
    \$paths = ['/usr/bin/', '/bin/', '/usr/sbin/', '/sbin/', '/usr/local/bin/'];
    foreach (\$list as \$name) {
        foreach (\$paths as \$path) {
            if (@file_exists(\$path . \$name)) return \$path . \$name;
        }
    }
    return \$list[0]; 
}

if (\$action === 'get_unlock') {
    \$file = __DIR__ . '/unlock_result.json';
    if (file_exists(\$file)) { echo file_get_contents(\$file); } 
    else { echo json_encode(['v4' => null, 'v6' => null]); }
    exit;
}

if (\$action === 'run_tool') {
    if (\$tool === 'iperf3') {
        \$port = rand(30000, 31000);
        // 尝试杀掉旧进程 (适配 root 运行的情况)
        exec("pkill -f 'iperf3 -s -p' > /dev/null 2>&1");
        
        \$bin = get_cmd('iperf3');
        // 使用 -D 守护进程模式启动 Server
        exec("\$bin -s -p \$port -1 -D > /dev/null 2>&1");
        
        // 等待一下确保启动
        usleep(300000); 
        
        \$server_ip = (\$proto === 'IPv6') ? \$PUBLIC_IP_V6 : \$PUBLIC_IP_V4;
        echo "iperf3 -c \$server_ip -p \$port";
        exit;
    }
    
    // 安全校验 Target (防注入)
    if (!preg_match('/^[a-zA-Z0-9\.\-\:]+\$/', \$target)) exit("Error: Invalid target.");
    
    \$flag = (\$proto === 'IPv6') ? '-6' : '-4';
    \$target = escapeshellarg(\$target);
    \$cmd = '';
    
    if (\$tool === 'ping') { 
        \$bin = get_cmd('ping'); 
        \$cmd = "\$bin \$flag -c 4 -w 10 \$target"; 
    } elseif (\$tool === 'mtr') { 
        \$bin = get_cmd('mtr'); 
        // mtr 通常需要 root 权限，如果在 root 下运行 php -S 没问题
        \$cmd = "\$bin \$flag -r -c 10 -n \$target"; 
    } else { 
        \$bin = get_cmd(['traceroute', 'tracepath']); 
        \$cmd = "\$bin \$flag -w 2 -q 1 -n \$target"; 
    }
    
    \$handle = popen("\$cmd 2>&1", 'r');
    if (is_resource(\$handle)) { 
        while (!feof(\$handle)) { 
            echo fgets(\$handle); 
            @flush(); 
        } 
        pclose(\$handle); 
    } else { 
        echo "Error: Failed to launch command: \$cmd"; 
    }
    exit;
}
echo "Agent Ready";
EOF

    echo -e "${YELLOW}正在生成 media_check.py (v3.0 Pro)...${NC}"

    # --- 生成 media_check.py (Hardcoded TikTok No / Strict Spotify) ---
    cat << 'EOF' > "$WEB_ROOT/media_check.py"
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import requests, re, socket, json, sys, argparse
import urllib3.util.connection as urllib3_cn

CURRENT_PROTOCOL = socket.AF_INET 
def allowed_gai_family(): return CURRENT_PROTOCOL
urllib3_cn.allowed_gai_family = allowed_gai_family

HEADERS = { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36', 'Accept-Language': 'en-US,en;q=0.9' }
COOKIES_YT = { 'CONSENT': 'YES+cb.20210328-17-p0.en+FX+416', 'SOCS': 'CAESEwgDEgk0ODE3Nzk3MjQaAmVuIAEaBgiA_LyaBg' }
TIMEOUT = 8 

def get_request(url, allow_redirects=True, use_cookies=False):
    try:
        cks = COOKIES_YT if use_cookies else {}
        with requests.Session() as s: return s.get(url, headers=HEADERS, cookies=cks, timeout=TIMEOUT, allow_redirects=allow_redirects)
    except:
        class M: text=""; status_code=0; url=url; history=[]
        return M()

def get_ip_info():
    try:
        d = requests.get("http://ip-api.com/json/", timeout=5).json()
        if d.get('countryCode'): return f"[{d.get('countryCode')}] {d.get('isp')}", d.get('countryCode')
    except: pass
    try: 
        ip = requests.get("https://api64.ipify.org?format=json", timeout=5).json().get('ip')
        if ip: return f"[Unknown] {ip}", "Unknown"
    except: pass
    return "Network Error", "Unknown"

def check_youtube(reg):
    r = get_request("https://www.youtube.com/", use_cookies=True)
    rg = "Unknown"
    if r.status_code == 200:
        m = re.search(r'"countryCode":"([A-Z]{2})"', r.text)
        if m: rg = m.group(1)
        else:
            m2 = re.search(r'"gl":"([A-Z]{2})"', r.text)
            if m2: rg = m2.group(1)
    if rg == "Unknown" and r.status_code == 0: return "Network Error"
    return f"Yes (Region: {rg})" if rg != "Unknown" else "No"

def check_netflix(reg):
    id = "70143836"
    def ex(u):
        m = re.search(r'netflix\.com/([a-z]{2}(-[a-z]{2})?)/', u)
        if m: return m.group(1).split('-')[0].upper()
        return reg if reg != "Unknown" else "US"
    r = get_request(f"https://www.netflix.com/title/{id}", use_cookies=False)
    if r.status_code == 200 and "/login" not in r.url and "Netflix" in r.text: return f"Yes (Region: {ex(r.url)})"
    if r.status_code == 403: return "No (IP Blocked)"
    return "No"

def check_disney(reg):
    r = get_request("https://www.disneyplus.com/")
    if r.status_code == 200 and "unavailable" not in r.url:
        rg = "Global"
        m = re.search(r'disneyplus\.com/([a-z]{2}-[a-z]{2})/', r.url)
        if m: rg = m.group(1).split('-')[1].upper()
        elif reg != "Unknown": rg = reg
        return f"Yes (Region: {rg})"
    return "No"

def check_tiktok(): 
    # 强制返回 No
    return "No"

def check_spotify():
    try:
        r = requests.get("https://spclient.wg.spotify.com/signup/public/v1/account/validate/password", headers=HEADERS, timeout=5)
        if r.status_code == 200: return "Yes"
        if r.status_code == 403: return "No"
    except: pass
    return "No"

def check_gemini():
    r = get_request("https://gemini.google.com", allow_redirects=True, use_cookies=True)
    if r.status_code == 200 and ("Google" in r.text or "Sign in" in r.text): return "Yes"
    if r.history and "accounts.google.com" in r.history[0].headers.get('Location', ''): return "Yes"
    return "No"

def run(p, n):
    global CURRENT_PROTOCOL; CURRENT_PROTOCOL = p
    print(f"Checking {n}...")
    ip, rg = get_ip_info()
    if "Network Error" in ip and n == "IPv6": rg = "Unknown"
    elif "Network Error" in ip: return {'netflix':"No",'youtube':"No",'disney':"No",'tiktok':"No",'spotify':"No",'gemini':"No"}
    return { 'netflix': check_netflix(rg), 'youtube': check_youtube(rg), 'disney': check_disney(rg), 'tiktok': check_tiktok(), 'spotify': check_spotify(), 'gemini': check_gemini() }

def main():
    parser = argparse.ArgumentParser(); parser.add_argument('--out', type=str); args = parser.parse_args()
    d = {}; d['v4'] = run(socket.AF_INET, "IPv4"); d['v6'] = run(socket.AF_INET6, "IPv6")
    if args.out:
        with open(args.out, 'w') as f: json.dump(d, f)
        import os; 
        try: os.chmod(args.out, 0o644) 
        except: pass

if __name__ == "__main__": main()
EOF

    chmod +x "$WEB_ROOT/media_check.py"

    # --- 生成 1GB 测速文件 ---
    if [ ! -f "$WEB_ROOT/1gb.bin" ]; then
        echo -e "${YELLOW}正在生成 1GB 测速文件 (可能需要几秒钟)...${NC}"
        # 优先使用 fallocate (瞬间生成)，不支持则用 dd
        if command -v fallocate &>/dev/null; then
            fallocate -l 1G "$WEB_ROOT/1gb.bin"
        else
            dd if=/dev/zero of="$WEB_ROOT/1gb.bin" bs=1M count=1024 status=progress
        fi
        echo -e "${GREEN}测速文件生成完毕。${NC}"
    fi

    # --- 设置 Crontab ---
    echo -e "${YELLOW}正在配置定时任务...${NC}"
    CRON_CMD="python3 $WEB_ROOT/media_check.py --out $WEB_ROOT/unlock_result.json"
    
    # 移除旧任务
    (crontab -l 2>/dev/null | grep -v "media_check.py") | crontab -
    
    # 添加新任务 (每30分钟)
    (crontab -l 2>/dev/null; echo "*/30 * * * * $CRON_CMD") | crontab -
    
    # 立即运行一次
    echo -e "${YELLOW}正在运行首次流媒体检测...${NC}"
    python3 "$WEB_ROOT/media_check.py" --out "$WEB_ROOT/unlock_result.json"

    echo -e "${GREEN}核心文件部署完成！${NC}"
}

# ==========================================
# 3. 服务管理 (内置 Server)
# ==========================================
function manage_service() {
    if [ -z "$WEB_ROOT" ]; then configure_node; fi
    
    echo ""
    echo "--- 节点服务管理 ---"
    echo "1. 启动 HTTP 服务 (Start)"
    echo "2. 停止 HTTP 服务 (Stop)"
    echo "3. 重启 HTTP 服务 (Restart)"
    echo "4. 查看状态 (Status)"
    echo "5. 返回主菜单"
    read -p "请选择: " svc_choice

    case $svc_choice in
        1)
            if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
                echo -e "${YELLOW}服务已在运行 (PID: $(cat $PID_FILE))${NC}"
            else
                if netstat -tuln | grep ":$NODE_PORT " > /dev/null; then
                     echo -e "${RED}端口 $NODE_PORT 已被占用！无法启动。${NC}"
                     return
                fi
                # 启动
                nohup php -S 0.0.0.0:$NODE_PORT -t "$WEB_ROOT" > "$LOG_FILE" 2>&1 &
                echo $! > "$PID_FILE"
                echo -e "${GREEN}服务已启动!${NC}"
                echo -e "Agent 地址: http://${IPV4:-YOUR_IP}:$NODE_PORT/agent.php"
            fi
            ;;
        2)
            if [ -f "$PID_FILE" ]; then
                kill $(cat "$PID_FILE") 2>/dev/null
                rm "$PID_FILE"
                echo -e "${GREEN}服务已停止。${NC}"
            else
                echo -e "${RED}服务未运行。${NC}"
            fi
            ;;
        3)
            if [ -f "$PID_FILE" ]; then kill $(cat "$PID_FILE") 2>/dev/null; rm "$PID_FILE"; fi
            nohup php -S 0.0.0.0:$NODE_PORT -t "$WEB_ROOT" > "$LOG_FILE" 2>&1 &
            echo $! > "$PID_FILE"
            echo -e "${GREEN}服务已重启!${NC}"
            ;;
        4)
            if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
                echo -e "${GREEN}状态: 运行中 (PID: $(cat $PID_FILE))${NC}"
            else
                echo -e "${RED}状态: 未运行${NC}"
            fi
            ;;
        *) return ;;
    esac
}

# ==========================================
# 主菜单
# ==========================================
check_env

while true; do
    echo ""
    echo "1. 配置安装参数 (目录/IP/密钥/端口)"
    echo "2. 安装/更新 节点文件 (Agent + 检测脚本)"
    echo "3. 服务管理 (启动/停止)"
    echo "4. 退出"
    read -p "请选择 [1-4]: " choice
    case $choice in
        1) configure_node ;;
        2) install_files ;;
        3) manage_service ;;
        4) exit 0 ;;
        *) echo -e "${RED}无效选项${NC}" ;;
    esac
done
