#!/bin/bash

# ==============================================================
# BitsFlowCloud Looking Glass Installer (Fix IP & CF Toggle)
# ==============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# === 资源链接 ===
REPO_URL="https://raw.githubusercontent.com/BitsFlowCloud/Looking-Glass/refs/heads/main"
URL_INDEX="$REPO_URL/index.php"
URL_API="$REPO_URL/api.php"
URL_AGENT="$REPO_URL/agent.php"
URL_CHECK="$REPO_URL/check_stream.py"
URL_TCP="$REPO_URL/tcp.sh"

[[ $EUID -ne 0 ]] && echo -e "${RED}Error: Must be run as root!${PLAIN}" && exit 1

# === 0. 自动获取公网 IP (增强版) ===
get_public_ips() {
    echo -e "${GREEN}>>> Detecting Server IP...${PLAIN}"
    
    # 1. 尝试 IPv4 (优先 ip.sb，伪装 User-Agent)
    SERVER_IP4=$(curl -sL -4 --max-time 5 --user-agent "Mozilla/5.0" http://ip.sb | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -n 1)
    
    # 2. 如果 ip.sb 失败，尝试备用源
    if [ -z "$SERVER_IP4" ]; then
        SERVER_IP4=$(curl -sL -4 --max-time 5 --user-agent "Mozilla/5.0" http://ifconfig.me | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -n 1)
    fi
    
    # 3. 实在获取不到，回退到 127.0.0.1
    [ -z "$SERVER_IP4" ] && SERVER_IP4="127.0.0.1"
    
    # 4. 尝试 IPv6
    SERVER_IP6=$(curl -sL -6 --max-time 5 --user-agent "Mozilla/5.0" http://ip.sb | grep -oE '([0-9a-fA-F]{0,4}:){1,7}[0-9a-fA-F]{0,4}' | head -n 1)
    [ -z "$SERVER_IP6" ] && SERVER_IP6=""

    echo -e "IPv4: ${CYAN}$SERVER_IP4${PLAIN}"
    echo -e "IPv6: ${CYAN}${SERVER_IP6:-None}${PLAIN}"
}

# === 1. 环境准备 ===
prepare_env() {
    echo -e "${GREEN}>>> Installing Dependencies...${PLAIN}"
    if [ -f /etc/debian_version ]; then
        apt-get update
        apt-get install -y nginx php-fpm php-cli php-curl php-json php-mbstring php-xml curl wget unzip python3 python3-pip iperf3 mtr-tiny iputils-ping
        WEB_USER="www-data"
        NGINX_CONF_DIR="/etc/nginx/sites-enabled"
        mkdir -p /etc/nginx/sites-enabled
    elif [ -f /etc/redhat-release ]; then
        yum install -y epel-release
        yum install -y nginx php-fpm php-cli php-common php-curl php-json php-mbstring php-xml curl wget unzip python3 python3-pip iperf3 mtr ping
        WEB_USER="nginx"
        NGINX_CONF_DIR="/etc/nginx/conf.d"
    else
        echo -e "${RED}Unsupported OS!${PLAIN}" && exit 1
    fi
    pip3 install requests >/dev/null 2>&1
    systemctl enable nginx php-fpm >/dev/null 2>&1
    systemctl start nginx php-fpm >/dev/null 2>&1
}

# === 2. 修复 PHP 配置 ===
fix_php_config() {
    echo -e "${GREEN}>>> Configuring PHP (Enabling exec, shell_exec...)${PLAIN}"
    PHP_INI=$(php --ini | grep "Loaded Configuration File" | awk -F: '{print $2}' | xargs)
    if [ -f "$PHP_INI" ]; then
        sed -i 's/exec,//g; s/shell_exec,//g; s/popen,//g; s/proc_open,//g' "$PHP_INI"
        sed -i 's/exec //g; s/shell_exec //g; s/popen //g; s/proc_open //g' "$PHP_INI"
        systemctl restart php*-fpm >/dev/null 2>&1 || systemctl restart php-fpm >/dev/null 2>&1
    fi
}

# === 3. 生成 Nginx 配置 (默认使用 IPv4) ===
setup_nginx_conf() {
    local SITE_NAME=$1
    local WEB_ROOT=$2

    echo -e "\n${YELLOW}--- Nginx Configuration ($SITE_NAME) ---${PLAIN}"
    
    # 默认使用检测到的 IPv4
    read -p "Enter Domain or IP (Default: $SERVER_IP4): " DOMAIN
    DOMAIN=${DOMAIN:-$SERVER_IP4}

    read -p "Enter Port (Default: 80): " PORT
    PORT=${PORT:-80}

    # 自动检测 PHP Socket
    PHP_SOCK=$(ls /run/php/php*-fpm.sock 2>/dev/null | head -n 1)
    if [ -z "$PHP_SOCK" ]; then
        if [ -S /run/php-fpm/www.sock ]; then PHP_SOCK="unix:/run/php-fpm/www.sock"; else PHP_SOCK="127.0.0.1:9000"; fi
    else
        PHP_SOCK="unix:$PHP_SOCK"
    fi
    echo -e "Detected PHP Backend: ${CYAN}$PHP_SOCK${PLAIN}"

    CONF_FILE="$NGINX_CONF_DIR/${SITE_NAME}.conf"
    
    cat > "$CONF_FILE" <<EOF
server {
    listen $PORT;
    server_name $DOMAIN;
    root $WEB_ROOT;
    index index.php index.html;

    access_log /var/log/nginx/${SITE_NAME}_access.log;
    error_log /var/log/nginx/${SITE_NAME}_error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass $PHP_SOCK;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    location ~ /\.ht { deny all; }
}
EOF
    
    nginx -t && systemctl restart nginx
    echo -e "${GREEN}Nginx Configured & Restarted!${PLAIN}"
}

clear
echo -e "${CYAN}=============================================================${PLAIN}"
echo -e "${CYAN}    BitsFlowCloud Looking Glass Installer (v2.2)${PLAIN}"
echo -e "${CYAN}=============================================================${PLAIN}"
echo -e "1. Install Master (Frontend) [主控端]"
echo -e "2. Install Agent (Node)      [被控端]"
echo -e "${CYAN}=============================================================${PLAIN}"
read -p "Select [1-2]: " install_type

# 初始化 IP
get_public_ips

# === 主控端安装 ===
install_master() {
    prepare_env
    fix_php_config

    DEFAULT_DIR="/var/www/html/lg"
    echo -e "\n${YELLOW}--- Installation Path ---${PLAIN}"
    read -p "Enter path (Default: $DEFAULT_DIR): " INSTALL_DIR
    INSTALL_DIR=${INSTALL_DIR:-$DEFAULT_DIR}
    mkdir -p "$INSTALL_DIR"
    
    echo -e "\n${YELLOW}--- Site Info ---${PLAIN}"
    read -p "Site Title: " SITE_TITLE
    read -p "Site Header: " SITE_HEADER
    read -p "Footer Text: " FOOTER_TEXT

    # === Cloudflare 配置 ===
    echo -e "\n${YELLOW}--- Security (Cloudflare Turnstile) ---${PLAIN}"
    read -p "Enable Cloudflare Turnstile? [y/N]: " ENABLE_CF
    if [[ "$ENABLE_CF" =~ ^[Yy]$ ]]; then
        CF_BOOL="true"
        read -p "Enter Site Key: " CF_SITE_KEY
        read -p "Enter Secret Key: " CF_SECRET_KEY
    else
        CF_BOOL="false"
        CF_SITE_KEY=""
        CF_SECRET_KEY=""
        echo -e "${YELLOW}Turnstile Disabled.${PLAIN}"
    fi

    # === 节点 1 配置 ===
    echo -e "\n${YELLOW}--- First Node Configuration ---${PLAIN}"
    read -p "Node Name (e.g. Hong Kong): " NODE_NAME
    read -p "Node Country Code (e.g. HK): " NODE_COUNTRY
    
    # 自动填充本机 IP
    read -p "Node IPv4 (Default: $SERVER_IP4): " NODE_IPV4
    NODE_IPV4=${NODE_IPV4:-$SERVER_IP4}
    
    read -p "Node IPv6 (Default: ${SERVER_IP6:-None}): " NODE_IPV6
    NODE_IPV6=${NODE_IPV6:-$SERVER_IP6}
    
    read -p "Agent URL (e.g. http://$NODE_IPV4/agent.php): " AGENT_URL
    [ -z "$AGENT_URL" ] && AGENT_URL="http://$NODE_IPV4/agent.php"
    
    read -p "Agent Key (Secret): " AGENT_KEY

    # === 下载文件 ===
    echo -e "\n${GREEN}>>> Downloading files...${PLAIN}"
    wget --no-check-certificate -O "$INSTALL_DIR/index.php" "$URL_INDEX"
    wget --no-check-certificate -O "$INSTALL_DIR/api.php" "$URL_API"

    # === 生成 Config.php (直接写入，确保格式正确) ===
    echo -e "${GREEN}>>> Generating config.php...${PLAIN}"
    cat > "$INSTALL_DIR/config.php" <<EOF
<?php
return [
    'site_title' => '$SITE_TITLE',
    'site_header' => '$SITE_HEADER',
    'footer_text' => '$FOOTER_TEXT',
    
    // Cloudflare Turnstile Configuration
    'enable_turnstile' => $CF_BOOL,
    'cf_site_key' => '$CF_SITE_KEY',
    'cf_secret_key' => '$CF_SECRET_KEY',

    // Nodes List
    'nodes' => [
        1 => [
            'name' => '$NODE_NAME',
            'country' => '$NODE_COUNTRY',
            'ipv4' => '$NODE_IPV4',
            'ipv6' => '$NODE_IPV6',
            'api_url' => '$AGENT_URL',
            'key' => '$AGENT_KEY'
        ]
    ]
];
EOF

    chown -R $WEB_USER:$WEB_USER "$INSTALL_DIR"
    chmod -R 755 "$INSTALL_DIR"

    # 配置 Nginx
    setup_nginx_conf "lg_master" "$INSTALL_DIR"

    echo -e "\n${GREEN}✅ Master Installed! Access via http://${DOMAIN}${PLAIN}"
}

# === 被控端安装 ===
install_agent() {
    prepare_env
    fix_php_config
    
    DEFAULT_DIR="/var/www/html/agent"
    echo -e "\n${YELLOW}--- Installation Path ---${PLAIN}"
    read -p "Enter path (Default: $DEFAULT_DIR): " INSTALL_DIR
    INSTALL_DIR=${INSTALL_DIR:-$DEFAULT_DIR}
    mkdir -p "$INSTALL_DIR"

    echo -e "\n${YELLOW}--- Agent Info ---${PLAIN}"
    read -p "Secret Key (Must match Master): " SECRET_KEY
    
    # 自动填充本机 IP
    read -p "Public IPv4 (Default: $SERVER_IP4): " PUB_IPV4
    PUB_IPV4=${PUB_IPV4:-$SERVER_IP4}
    
    read -p "Public IPv6 (Default: ${SERVER_IP6:-None}): " PUB_IPV6
    PUB_IPV6=${PUB_IPV6:-$SERVER_IP6}

    echo -e "\n${GREEN}>>> Downloading files...${PLAIN}"
    wget --no-check-certificate -O "$INSTALL_DIR/agent.php" "$URL_AGENT"
    wget --no-check-certificate -O "$INSTALL_DIR/check_stream.py" "$URL_CHECK"

    # 配置 Agent
    sed -i "s#\$SECRET_KEY\s*=\s*'';#\$SECRET_KEY   = '$SECRET_KEY';#g" "$INSTALL_DIR/agent.php"
    sed -i "s#\$PUBLIC_IP_V4\s*=\s*'';#\$PUBLIC_IP_V4 = '$PUB_IPV4';#g" "$INSTALL_DIR/agent.php"
    sed -i "s#\$PUBLIC_IP_V6\s*=\s*'';#\$PUBLIC_IP_V6 = '$PUB_IPV6';#g" "$INSTALL_DIR/agent.php"

    # 生成测试文件
    echo -e "${GREEN}>>> Generating 1GB test file...${PLAIN}"
    if [ ! -f "$INSTALL_DIR/1gb.bin" ]; then
        dd if=/dev/zero of="$INSTALL_DIR/1gb.bin" bs=1M count=1000 status=progress
    fi

    # 运行流媒体检测
    echo -e "${GREEN}>>> Running Stream Check...${PLAIN}"
    chmod +x "$INSTALL_DIR/check_stream.py"
    python3 "$INSTALL_DIR/check_stream.py" --out "$INSTALL_DIR/unlock_result.json"
    
    # Crontab
    CRON_CMD="*/30 * * * * /usr/bin/python3 $INSTALL_DIR/check_stream.py --out $INSTALL_DIR/unlock_result.json >/dev/null 2>&1"
    (crontab -l 2>/dev/null | grep -v "check_stream.py"; echo "$CRON_CMD") | crontab -

    # TCP 优化
    echo -e "\n${GREEN}>>> Running TCP Optimization...${PLAIN}"
    wget --no-check-certificate -O /tmp/tcp.sh "$URL_TCP"
    [ -f /tmp/tcp.sh ] && bash /tmp/tcp.sh && rm -f /tmp/tcp.sh

    chown -R $WEB_USER:$WEB_USER "$INSTALL_DIR"
    chmod -R 755 "$INSTALL_DIR"

    # 配置 Nginx
    setup_nginx_conf "lg_agent" "$INSTALL_DIR"

    echo -e "\n${GREEN}✅ Agent Installed! URL: http://${DOMAIN}/agent.php${PLAIN}"
}

case $install_type in
    1) install_master ;;
    2) install_agent ;;
    *) echo -e "${RED}Invalid selection!${PLAIN}" ;;
esac
