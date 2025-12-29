#!/bin/bash

# ==========================================
# GitHub 仓库配置 (已修正 Config 为 Raw 链接)
# ==========================================
REPO_URL_INDEX="https://raw.githubusercontent.com/BitsFlowCloud/Looking-Glass/refs/heads/main/index.php"
REPO_URL_CONFIG="https://raw.githubusercontent.com/BitsFlowCloud/Looking-Glass/refs/heads/main/config.php.example"

# ==========================================
# 颜色与默认配置
# ==========================================
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

DEFAULT_DIR="/root/www/wwwroot/lg-master"
DEFAULT_TITLE="My Looking Glass"
DEFAULT_HEADER="BITSFLOW NETWORK"
DEFAULT_PORT=8080

SETTINGS_FILE="/root/.lg_master_settings"
PID_FILE="/tmp/lg-master.pid"
LOG_FILE="/tmp/lg-master.log"
NGINX_CONF="/etc/nginx/conf.d/lg_master.conf"

# ==========================================
# 0. 环境检查
# ==========================================
function check_env() {
    if [[ $EUID -ne 0 ]]; then echo -e "${RED}错误: 请使用 root 用户。${NC}"; exit 1; fi
    if ! command -v php &> /dev/null; then
        echo -e "${YELLOW}正在安装 PHP 及必要组件...${NC}"
        if [ -f /etc/debian_version ]; then 
            apt-get update && apt-get install -y php-cli php-curl php-json curl
        elif [ -f /etc/redhat-release ]; then 
            yum install -y php-cli php-common php-curl php-json curl
        fi
    fi
}

# ==========================================
# 1. 配置向导
# ==========================================
function configure_install() {
    echo -e "${YELLOW}>>> 进入配置向导${NC}"
    
    read -p "1. 安装目录 [$DEFAULT_DIR]: " INPUT_DIR
    WEB_ROOT=${INPUT_DIR:-$DEFAULT_DIR}
    
    read -p "2. 浏览器标签标题 [$DEFAULT_TITLE]: " INPUT_TITLE
    SITE_TITLE=${INPUT_TITLE:-$DEFAULT_TITLE}

    read -p "3. 页面特效大字 [$DEFAULT_HEADER]: " INPUT_HEADER
    SITE_HEADER=${INPUT_HEADER:-$DEFAULT_HEADER}
    
    while true; do
        read -p "4. CF Turnstile Site Key (必填): " INPUT_CF
        if [ -n "$INPUT_CF" ]; then CF_SITE_KEY="$INPUT_CF"; break; else echo -e "${RED}不能为空${NC}"; fi
    done
    
    read -p "5. PHP 本地监听端口 [$DEFAULT_PORT]: " INPUT_PORT
    SERVER_PORT=${INPUT_PORT:-$DEFAULT_PORT}

    # 保存配置到本地文件
    echo "WEB_ROOT=\"$WEB_ROOT\"" > "$SETTINGS_FILE"
    echo "SERVER_PORT=\"$SERVER_PORT\"" >> "$SETTINGS_FILE"
    echo "SITE_TITLE=\"$SITE_TITLE\"" >> "$SETTINGS_FILE"
    echo "SITE_HEADER=\"$SITE_HEADER\"" >> "$SETTINGS_FILE"
    echo "CF_SITE_KEY=\"$CF_SITE_KEY\"" >> "$SETTINGS_FILE"
    
    echo -e "${GREEN}配置已保存，请执行安装步骤。${NC}"
}

# ==========================================
# 2. 安装/更新 (从 GitHub 拉取)
# ==========================================
function install_files() {
    if [ ! -f "$SETTINGS_FILE" ]; then configure_install; fi
    source "$SETTINGS_FILE"
    if [ ! -d "$WEB_ROOT" ]; then mkdir -p "$WEB_ROOT"; fi

    echo -e "${YELLOW}正在从 GitHub 下载核心文件...${NC}"

    # 1. 下载 index.php
    wget -O "$WEB_ROOT/index.php" "$REPO_URL_INDEX"
    if [ $? -ne 0 ]; then echo -e "${RED}index.php 下载失败，请检查网络或链接${NC}"; return; fi

    # 2. 处理 config.php
    CONFIG_FILE="$WEB_ROOT/config.php"
    
    # 下载模板
    wget -O "$WEB_ROOT/config.php.example" "$REPO_URL_CONFIG"
    if [ $? -ne 0 ]; then echo -e "${RED}config.php.example 下载失败${NC}"; return; fi

    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${YELLOW}生成新的 config.php...${NC}"
        cp "$WEB_ROOT/config.php.example" "$CONFIG_FILE"
    else
        echo -e "${YELLOW}更新现有 config.php (保留节点数据)...${NC}"
    fi

    # 使用 sed 替换配置项
    # 注意：这里适配了你在 GitHub 上 config.php.example 的键名
    sed -i "s/'site_title' => .*/'site_title' => '$SITE_TITLE',/" "$CONFIG_FILE"
    sed -i "s/'site_header' => .*/'site_header' => '$SITE_HEADER',/" "$CONFIG_FILE"
    sed -i "s/'cf_site_key' => .*/'cf_site_key' => '$CF_SITE_KEY',/" "$CONFIG_FILE"

    # 3. 生成 api.php (本地生成，确保后端逻辑存在)
    cat << 'EOF' > "$WEB_ROOT/api.php"
<?php
error_reporting(0);
header('Content-Type: application/json; charset=utf-8');
$config = require 'config.php';
$action = $_POST['action'] ?? '';

if ($action === 'get_nodes') {
    $nodes = $config['nodes']; $final_nodes = [];
    foreach ($nodes as $id => $node) {
        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, $node['api_url']);
        curl_setopt($ch, CURLOPT_POST, 1);
        curl_setopt($ch, CURLOPT_POSTFIELDS, http_build_query(['key' => $node['key'], 'action' => 'get_unlock']));
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, 2);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        $resp = curl_exec($ch);
        $code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        $node['unlock'] = ($code == 200 && $resp) ? json_decode($resp, true) : ['v4' => null, 'v6' => null];
        unset($node['key'], $node['api_url']);
        $final_nodes[$id] = $node;
    }
    echo json_encode(['status' => 'success', 'data' => $final_nodes]);
    exit;
}

if ($action === 'run_tool') {
    $nid = $_POST['node_id'] ?? '';
    if (!isset($config['nodes'][$nid])) { echo json_encode(['status' => 'error', 'message' => 'Node not found']); exit; }
    $n = $config['nodes'][$nid];
    $p = $_POST; $p['key'] = $n['key'];
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $n['api_url']);
    curl_setopt($ch, CURLOPT_POST, 1);
    curl_setopt($ch, CURLOPT_POSTFIELDS, http_build_query($p));
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 45);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
    echo curl_exec($ch);
    curl_close($ch);
    exit;
}
echo json_encode(['status' => 'error', 'message' => 'Invalid action']);
EOF

    chmod -R 755 "$WEB_ROOT"
    echo -e "${GREEN}安装/更新完成！${NC}"
}

# ==========================================
# 3. 添加节点
# ==========================================
function add_node() {
    if [ ! -f "$SETTINGS_FILE" ]; then configure_install; fi
    source "$SETTINGS_FILE"
    CONFIG_FILE="$WEB_ROOT/config.php"

    if [ ! -f "$CONFIG_FILE" ]; then echo -e "${RED}请先执行安装步骤。${NC}"; return; fi
    
    echo -e "${YELLOW}--- 添加新节点 ---${NC}"
    read -p "节点 ID (例如 de01): " N_ID
    read -p "显示名称 (例如 Frankfurt): " N_NAME
    read -p "国家代码 (例如 de): " N_FLAG
    read -p "IPv4 地址: " N_IP4
    read -p "IPv6 地址 (可选): " N_IP6
    read -p "API URL (例如 http://1.2.3.4/agent.php): " N_API
    read -p "通信密钥: " N_KEY

    # 构造 PHP 数组项
    NEW_NODE_STR="        '$N_ID' => ['name'=>'$N_NAME','country'=>'$N_FLAG','ipv4'=>'$N_IP4','ipv6'=>'$N_IP6','api_url'=>'$N_API','key'=>'$N_KEY'],"
    
    # 插入到 'nodes' => [ 的下一行
    sed -i "/'nodes' => \[/a $NEW_NODE_STR" "$CONFIG_FILE"
    
    echo -e "${GREEN}节点已添加。${NC}"
}

# ==========================================
# 4. 服务管理
# ==========================================
function manage_service() {
    if [ ! -f "$SETTINGS_FILE" ]; then configure_install; fi
    source "$SETTINGS_FILE"

    echo ""
    echo "1. 启动 Web 服务"
    echo "2. 停止 Web 服务"
    echo "3. 重启 Web 服务"
    echo "4. 查看状态"
    echo "5. 配置 SSL (HTTPS/Nginx)"
    read -p "选择: " OPT

    case $OPT in
        1)
            if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
                echo "服务已在运行"; return
            fi
            nohup php -S 127.0.0.1:$SERVER_PORT -t "$WEB_ROOT" > "$LOG_FILE" 2>&1 &
            echo $! > "$PID_FILE"
            echo -e "${GREEN}已启动 (端口 $SERVER_PORT)${NC}"
            ;;
        2)
            if [ -f "$PID_FILE" ]; then kill $(cat "$PID_FILE") 2>/dev/null; rm "$PID_FILE"; fi
            echo -e "${GREEN}已停止${NC}"
            ;;
        3)
            if [ -f "$PID_FILE" ]; then kill $(cat "$PID_FILE") 2>/dev/null; rm "$PID_FILE"; fi
            nohup php -S 127.0.0.1:$SERVER_PORT -t "$WEB_ROOT" > "$LOG_FILE" 2>&1 &
            echo $! > "$PID_FILE"
            echo -e "${GREEN}已重启${NC}"
            ;;
        4)
            if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
                echo -e "${GREEN}运行中 (PID: $(cat $PID_FILE))${NC}"
            else
                echo -e "${RED}未运行${NC}"
            fi
            ;;
        5)
            read -p "请输入域名: " DOMAIN
            read -p "请输入邮箱: " EMAIL
            
            # 确保后端已启动
            if [ ! -f "$PID_FILE" ]; then 
                nohup php -S 127.0.0.1:$SERVER_PORT -t "$WEB_ROOT" > "$LOG_FILE" 2>&1 &
                echo $! > "$PID_FILE"
            fi

            echo "安装 Nginx & Certbot..."
            if [ -f /etc/debian_version ]; then apt-get install -y nginx python3-certbot-nginx; 
            elif [ -f /etc/redhat-release ]; then yum install -y nginx python3-certbot-nginx; fi
            
            echo "生成 Nginx 配置..."
            cat << EOF > $NGINX_CONF
server {
    listen 80;
    server_name $DOMAIN;
    location / {
        proxy_pass http://127.0.0.1:$SERVER_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF
            systemctl restart nginx
            certbot --nginx -d "$DOMAIN" -m "$EMAIL" --agree-tos --non-interactive
            ;;
    esac
}

# ==========================================
# 主菜单
# ==========================================
check_env

while true; do
    echo ""
    echo "--- BitsFlowCloud Looking Glass 管理脚本 ---"
    echo "1. 配置安装参数 (目录/标题/Keys)"
    echo "2. 安装/更新 (从 GitHub 下载)"
    echo "3. 添加节点"
    echo "4. 服务管理 (启动/停止/SSL)"
    echo "5. 退出"
    read -p "请选择: " CHOICE
    
    case $CHOICE in
        1) configure_install ;;
        2) install_files ;;
        3) add_node ;;
        4) manage_service ;;
        5) exit ;;
    esac
done
