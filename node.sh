#!/bin/bash
# ==========================================
# 颜色配置
# ==========================================
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
# ==========================================
# 默认配置
# ==========================================
DEFAULT_DIR="/root/lg-agent"
DEFAULT_PORT=80
DEFAULT_KEY="123456"
SETTINGS_FILE="/root/.lg_agent_settings"
PID_FILE_PHP="/tmp/lg-agent-php.pid"
PID_FILE_IPERF="/tmp/lg-agent-iperf.pid"
LOG_FILE="/tmp/lg-agent.log"
NGINX_CONF="/etc/nginx/conf.d/lg_agent.conf"
# ==========================================
# 0. 环境检查 & 依赖安装
# ==========================================
function check_env() {
    if [[ $EUID -ne 0 ]]; then echo -e "${RED}错误: 请使用 root 用户。${NC}"; exit 1; fi
    
    echo -e "${YELLOW}正在更新软件源并安装依赖...${NC}"
    if [ -f /etc/debian_version ]; then
        apt-get update -q
        apt-get install -y nginx php-cli php-curl php-json curl mtr-tiny iperf3 iputils-ping traceroute cron
    elif [ -f /etc/redhat-release ]; then
        yum install -y epel-release
        yum install -y nginx php-cli php-common php-curl php-json curl mtr iperf3 iputils traceroute crontabs
    fi
    
    # 确保 iperf3 安装成功
    if ! command -v iperf3 &> /dev/null; then
        echo -e "${RED}Iperf3 安装失败，尝试编译安装或检查源。${NC}"
    fi
}
# ==========================================
# 1. 配置向导
# ==========================================
function configure_agent() {
    while true; do
        clear
        echo -e "${YELLOW}>>> 被控端配置向导${NC}"
        echo "1. 设置参数"
        echo "0. 返回主菜单"
        read -p "请选择: " OPT
        
        if [ "$OPT" == "0" ]; then return; fi
        if [ "$OPT" == "1" ]; then
            read -p "1. 安装目录 [$DEFAULT_DIR]: " INPUT_DIR
            AGENT_ROOT=${INPUT_DIR:-$DEFAULT_DIR}
            
            read -p "2. Nginx 监听端口 (HTTP) [$DEFAULT_PORT]: " INPUT_PORT
            AGENT_PORT=${INPUT_PORT:-$DEFAULT_PORT}
            echo -e "${YELLOW}注意：此密钥必须与主控端 config.php 中填写的 key 一致！${NC}"
            read -p "3. 通信密钥 (API Key): " INPUT_KEY
            AGENT_KEY=${INPUT_KEY:-$DEFAULT_KEY}
            # 保存配置
            echo "AGENT_ROOT=\"$AGENT_ROOT\"" > "$SETTINGS_FILE"
            echo "AGENT_PORT=\"$AGENT_PORT\"" >> "$SETTINGS_FILE"
            echo "AGENT_KEY=\"$AGENT_KEY\"" >> "$SETTINGS_FILE"
            
            echo -e "${GREEN}配置已保存！请执行 [2. 安装/更新] 步骤。${NC}"
            read -p "按回车键返回..."
            return
        fi
    done
}
# ==========================================
# 2. 安装核心文件
# ==========================================
function install_files() {
    if [ ! -f "$SETTINGS_FILE" ]; then echo -e "${RED}请先配置参数。${NC}"; read; return; fi
    source "$SETTINGS_FILE"
    
    if [ ! -d "$AGENT_ROOT" ]; then mkdir -p "$AGENT_ROOT"; fi
    echo -e "${YELLOW}1. 生成 agent.php (API 接口)...${NC}"
    
    # --- agent.php ---
    cat > "$AGENT_ROOT/agent.php" <<EOF
<?php
error_reporting(0);
ini_set('display_errors', 0);
ini_set('max_execution_time', 60);
// 获取配置的密钥
\$AUTH_KEY = '$AGENT_KEY';
// 1. 鉴权
\$req_key = \$_POST['key'] ?? '';
if (\$req_key !== \$AUTH_KEY) {
    http_response_code(403);
    die("Authorization Failed");
}
\$action = \$_POST['action'] ?? '';
// 2. 获取流媒体解锁状态 (读取 json 文件)
if (\$action === 'get_unlock') {
    header('Content-Type: application/json');
    \$json_file = 'unlock.json';
    if (file_exists(\$json_file)) {
        echo file_get_contents(\$json_file);
    } else {
        echo json_encode(['message' => 'Checking...']);
    }
    exit;
}
// 3. 执行网络工具
if (\$action === 'run_tool') {
    header('Content-Type: text/plain');
    
    \$tool = \$_POST['tool'] ?? '';
    \$target = \$_POST['target'] ?? '';
    \$proto = \$_POST['proto'] ?? 'IPv4';
    // 安全过滤：只允许字母、数字、点、冒号、横杠
    if (!preg_match('/^[a-zA-Z0-9.:-]+$/', \$target)) {
        die("Invalid Target Format");
    }
    \$cmd = '';
    switch (\$tool) {
        case 'ping':
            // 区分 IPv4/IPv6
            \$is_v6 = (strpos(\$target, ':') !== false);
            \$ping_bin = \$is_v6 ? 'ping6' : 'ping';
            // -c 4 次数, -w 5 超时
            \$cmd = "\$ping_bin -c 4 -w 5 " . escapeshellarg(\$target);
            break;
            
        case 'mtr':
            // -r 报告模式, -c 1 (快速), -n 不解析
            \$cmd = "mtr -r -c 1 -n " . escapeshellarg(\$target);
            break;
            
        case 'route':
            \$cmd = "traceroute -w 2 -q 1 -m 20 " . escapeshellarg(\$target);
            break;
            
        case 'iperf3':
            // 主控端请求 iperf3 时，我们返回连接命令给用户
            // 确保本地 iperf3 服务端已开启
            \$my_ip = \$_SERVER['SERVER_ADDR'] ?? 'NODE_IP';
            // 尝试获取公网IP (如果是在 NAT 后)
            if (\$my_ip == '127.0.0.1') {
                \$my_ip = file_get_contents('http://ifconfig.me/ip'); 
            }
            
            echo "Run this command on your machine:\n\n";
            echo "iperf3 -c \$my_ip -p $AGENT_PORT -R"; // 注意：端口复用或单独端口需配置，这里简化为提示
            echo "\n\n(Note: Server daemon is running on default port 5201 if valid)";
            exit;
            break;
            
        default:
            die("Unknown Tool");
    }
    if (\$cmd) {
        // 执行命令并返回输出
        echo shell_exec(\$cmd . " 2>&1");
    }
    exit;
}
EOF
    echo -e "${YELLOW}2. 生成 monitor.sh (流媒体检测脚本)...${NC}"
    # --- monitor.sh ---
    cat > "$AGENT_ROOT/monitor.sh" << 'EOF_MONITOR'
#!/bin/bash
# 简单的流媒体检测脚本 - 生成 unlock.json
# 移除了 TikTok 强制 No 的逻辑，改为真实检测
cd "$(dirname "$0")"
OUT_FILE="unlock.json"
# 辅助函数：检测 URL 返回码
check_http() {
    local url=$1
    local code=$(curl -o /dev/null -s -w "%{http_code}\n" --max-time 5 "$url")
    if [[ "$code" == "200" ]] || [[ "$code" == "301" ]] || [[ "$code" == "302" ]]; then
        echo "Yes"
    else
        echo "No"
    fi
}
# 1. Netflix (检测 fast.com 及其 CDN 分流)
# 这是一个简化的检测，更精准的需要检测 API
check_netflix() {
    local result=$(curl -s --max-time 5 https://www.netflix.com/title/80018499 -I | grep "location")
    if [[ -n "$result" ]]; then
        echo "Yes"
    else
        echo "No"
    fi
}
# 2. YouTube (检测是否被重定向到 google.cn 或者 403)
check_youtube() {
    local code=$(curl -o /dev/null -s -w "%{http_code}\n" --max-time 5 "https://www.youtube.com")
    if [[ "$code" == "200" ]]; then
        # 尝试检测地区
        local region=$(curl -s --max-time 5 "https://www.youtube.com" | grep -oP '"countryCode":"\K[A-Z]{2}')
        if [[ -n "$region" ]]; then
            echo "Yes (Region: $region)"
        else
            echo "Yes"
        fi
    else
        echo "No"
    fi
}
# 3. TikTok (真实检测)
check_tiktok() {
    # 尝试访问 tiktok.com，如果返回 200 或 301 且没有被重定向到 access_denied
    local result=$(curl -I -s --max-time 5 "https://www.tiktok.com/")
    if echo "$result" | grep -q "HTTP/2 200"; then
        echo "Yes"
    elif echo "$result" | grep -q "HTTP/1.1 200"; then
        echo "Yes"
    else
        echo "No"
    fi
}
# 4. Disney+
check_disney() {
    local code=$(curl -o /dev/null -s -w "%{http_code}\n" --max-time 5 "https://www.disneyplus.com")
    if [[ "$code" == "200" ]]; then echo "Yes"; else echo "No"; fi
}
# 5. Gemini / OpenAI
check_ai() {
    local code=$(curl -o /dev/null -s -w "%{http_code}\n" --max-time 5 "https://gemini.google.com")
    if [[ "$code" == "200" ]] || [[ "$code" == "302" ]]; then echo "Yes"; else echo "No"; fi
}
# 执行检测
NETFLIX=$(check_netflix)
YOUTUBE=$(check_youtube)
TIKTOK=$(check_tiktok)
DISNEY=$(check_disney)
GEMINI=$(check_ai)
SPOTIFY=$(check_http "https://www.spotify.com")
# 生成 JSON
cat > "$OUT_FILE" << JSON
{
    "netflix": "$NETFLIX",
    "youtube": "$YOUTUBE",
    "tiktok": "$TIKTOK",
    "disney": "$DISNEY",
    "gemini": "$GEMINI",
    "spotify": "$SPOTIFY"
}
JSON
EOF_MONITOR
    chmod +x "$AGENT_ROOT/monitor.sh"
    echo -e "${YELLOW}3. 生成测速文件 (1GB)...${NC}"
    # 使用 seek 瞬间生成空洞文件，不占用真实 IO
    dd if=/dev/zero of="$AGENT_ROOT/1gb.bin" bs=1 count=0 seek=1G
    echo -e "${YELLOW}4. 配置 Crontab (每30分钟更新解锁状态)...${NC}"
    (crontab -l 2>/dev/null | grep -v "monitor.sh") | crontab -
    (crontab -l 2>/dev/null; echo "*/30 * * * * bash $AGENT_ROOT/monitor.sh >/dev/null 2>&1") | crontab -
    
    # 立即运行一次检测
    bash "$AGENT_ROOT/monitor.sh" &
    echo -e "${GREEN}核心文件安装完成。${NC}"
    read -p "按回车键返回..."
}
# ==========================================
# 3. 配置 Nginx 与服务
# ==========================================
function configure_service() {
    if [ ! -f "$SETTINGS_FILE" ]; then echo -e "${RED}请先配置参数。${NC}"; read; return; fi
    source "$SETTINGS_FILE"
    echo -e "${YELLOW}正在配置 Nginx...${NC}"
    
    # 获取 PHP 本地监听端口 (随机一个高位端口，仅供本地 Nginx 连接)
    PHP_LOCAL_PORT=12345
    cat > "$NGINX_CONF" <<EOF
server {
    listen $AGENT_PORT;
    listen [::]:$AGENT_PORT;
    server_name _;
    
    root $AGENT_ROOT;
    index agent.php;
    # 安全配置：隐藏 Nginx 版本
    server_tokens off;
    # 1. 测速文件直接由 Nginx 处理 (高性能)
    location = /1gb.bin {
        try_files \$uri =404;
        # 允许跨域 (如果需要)
        add_header Access-Control-Allow-Origin *;
    }
    # 2. PHP 反向代理 (代理到本地 PHP 内置服务器)
    location ~ \.php$ {
        proxy_pass http://127.0.0.1:$PHP_LOCAL_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
    # 3. 安全加固：禁止访问敏感文件
    location ~ ^/(\.git|monitor\.sh|unlock\.json|.*\.log) {
        deny all;
        return 404;
    }
    
    location ~ /\. {
        deny all;
    }
}
EOF
    echo -e "${YELLOW}正在启动服务...${NC}"
    
    # 1. 重启 Nginx
    systemctl enable nginx
    systemctl restart nginx
    # 2. 启动/重启 PHP 内置服务器 (仅监听 127.0.0.1)
    if [ -f "$PID_FILE_PHP" ]; then kill $(cat "$PID_FILE_PHP") 2>/dev/null; fi
    nohup php -S 127.0.0.1:$PHP_LOCAL_PORT -t "$AGENT_ROOT" > /dev/null 2>&1 &
    echo $! > "$PID_FILE_PHP"
    # 3. 启动 Iperf3 服务端 (监听默认 5201)
    if [ -f "$PID_FILE_IPERF" ]; then kill $(cat "$PID_FILE_IPERF") 2>/dev/null; fi
    nohup iperf3 -s > /dev/null 2>&1 &
    echo $! > "$PID_FILE_IPERF"
    echo -e "${GREEN}服务已启动！${NC}"
    echo -e "API 地址: http://[你的IP]:$AGENT_PORT/agent.php"
    echo -e "密钥: $AGENT_KEY"
    read -p "按回车键返回..."
}
# ==========================================
# 4. 服务管理
# ==========================================
function manage_service() {
    source "$SETTINGS_FILE" 2>/dev/null
    PHP_LOCAL_PORT=12345
    
    while true; do
        clear
        echo -e "${YELLOW}--- 服务管理 ---${NC}"
        echo "1. 重启所有服务 (Nginx, PHP, Iperf3)"
        echo "2. 停止所有服务"
        echo "3. 查看状态"
        echo "4. 手动更新流媒体解锁状态"
        echo "0. 返回主菜单"
        read -p "选择: " OPT
        
        case $OPT in
            1)
                systemctl restart nginx
                if [ -f "$PID_FILE_PHP" ]; then kill $(cat "$PID_FILE_PHP") 2>/dev/null; fi
                nohup php -S 127.0.0.1:$PHP_LOCAL_PORT -t "$AGENT_ROOT" > /dev/null 2>&1 &
                echo $! > "$PID_FILE_PHP"
                
                if [ -f "$PID_FILE_IPERF" ]; then kill $(cat "$PID_FILE_IPERF") 2>/dev/null; fi
                nohup iperf3 -s > /dev/null 2>&1 &
                echo $! > "$PID_FILE_IPERF"
                echo -e "${GREEN}已重启。${NC}"
                read -p "按回车..."
                ;;
            2)
                systemctl stop nginx
                if [ -f "$PID_FILE_PHP" ]; then kill $(cat "$PID_FILE_PHP") 2>/dev/null; rm "$PID_FILE_PHP"; fi
                if [ -f "$PID_FILE_IPERF" ]; then kill $(cat "$PID_FILE_IPERF") 2>/dev/null; rm "$PID_FILE_IPERF"; fi
                echo -e "${YELLOW}服务已停止。${NC}"
                read -p "按回车..."
                ;;
            3)
                systemctl status nginx --no-pager
                echo "PHP PID: $(cat $PID_FILE_PHP 2>/dev/null)"
                ps aux | grep php | grep -v grep
                read -p "按回车..."
                ;;
            4)
                echo "正在检测..."
                bash "$AGENT_ROOT/monitor.sh"
                cat "$AGENT_ROOT/unlock.json"
                echo ""
                read -p "按回车..."
                ;;
            0) return ;;
        esac
    done
}
# ==========================================
# 主菜单
# ==========================================
check_env
while true; do
    clear
    echo -e "${GREEN}=============================================${NC}"
    echo -e "${GREEN}   Looking Glass 被控端 (Agent) 管理脚本${NC}"
    echo -e "${GREEN}=============================================${NC}"
    echo "1. 配置参数 (端口/密钥)"
    echo "2. 安装核心文件 (Agent/Monitor)"
    echo "3. 配置 Nginx 并启动服务"
    echo "4. 服务管理 / 手动检测"
    echo "0. 退出"
    echo -e "${GREEN}=============================================${NC}"
    read -p "请选择: " CHOICE
    
    case $CHOICE in
        1) configure_agent ;;
        2) install_files ;;
        3) configure_service ;;
        4) manage_service ;;
        0) exit ;;
        *) echo "无效选择"; sleep 1 ;;
    esac
done
