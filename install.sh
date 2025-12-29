#!/bin/bash

# ==============================================================
# BitsFlowCloud Looking Glass Installer (Final Stable)
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
URL_CONFIG="$REPO_URL/config.php"
URL_AGENT="$REPO_URL/agent.php"
URL_CHECK="$REPO_URL/check_stream.py"
URL_TCP="$REPO_URL/tcp.sh"

[[ $EUID -ne 0 ]] && echo -e "${RED}Error: Must be run as root!${PLAIN}" && exit 1

# === 1. 环境准备与依赖安装 ===
prepare_env() {
    echo -e "${GREEN}>>> Checking & Installing Dependencies...${PLAIN}"
    
    if [ -f /etc/debian_version ]; then
        apt-get update
        apt-get install -y nginx php-fpm php-cli php-curl php-json php-mbstring php-xml curl wget unzip python3 python3-pip iperf3 mtr-tiny iputils-ping
        WEB_USER="www-data"
        NGINX_CONF_DIR="/etc/nginx/sites-enabled"
        # 确保 sites-enabled 存在
        mkdir -p /etc/nginx/sites-enabled
    elif [ -f /etc/redhat-release ]; then
        yum install -y epel-release
        yum install -y nginx php-fpm php-cli php-common php-curl php-json php-mbstring php-xml curl wget unzip python3 python3-pip iperf3 mtr ping
        WEB_USER="nginx"
        NGINX_CONF_DIR="/etc/nginx/conf.d"
    else
        echo -e "${RED}Unsupported OS!${PLAIN}" && exit 1
    fi
    
    # 安装 Python 依赖
    pip3 install requests >/dev/null 2>&1

    # 启动 PHP 和 Nginx
    systemctl enable nginx php-fpm >/dev/null 2>&1
    systemctl start nginx php-fpm >/dev/null 2>&1
}

# === 2. 自动修复 PHP 配置 ===
fix_php_config() {
    echo -e "${GREEN}>>> Configuring PHP (Enabling exec, shell_exec...)${PLAIN}"
    PHP_INI=$(php --ini | grep "Loaded Configuration File" | awk -F: '{print $2}' | xargs)
    if [ -f "$PHP_INI" ]; then
        sed -i 's/exec,//g; s/shell_exec,//g; s/popen,//g; s/proc_open,//g' "$PHP_INI"
        sed -i 's/exec //g; s/shell_exec //g; s/popen //g; s/proc_open //g' "$PHP_INI"
        # 重启 PHP
        systemctl restart php*-fpm >/dev/null 2>&1 || systemctl restart php-fpm >/dev/null 2>&1
    fi
}

# === 3. 智能生成 Nginx 配置 (交互式) ===
setup_nginx_conf() {
    local SITE_NAME=$1
    local WEB_ROOT=$2

    echo -e "\n${YELLOW}--- Nginx Configuration ($SITE_NAME) ---${PLAIN}"
    echo -e "We will now generate the Nginx config file automatically."
    
    # 1. 获取域名/IP
    read -p "Enter Domain or IP (Default: _ ): " DOMAIN
    DOMAIN=${DOMAIN:-_}

    # 2. 获取端口
    read -p "Enter Port (Default: 80): " PORT
    PORT=${PORT:-80}

    # 3. 自动检测 PHP Socket
    PHP_SOCK=$(ls /run/php/php*-fpm.sock 2>/dev/null | head -n 1)
    if [ -z "$PHP_SOCK" ]; then
        # 如果找不到 sock，尝试找 CentOS 的默认位置或 TCP 方式
        if [ -S /run/php-fpm/www.sock ]; then
            PHP_SOCK="unix:/run/php-fpm/www.sock"
        else
            PHP_SOCK="127.0.0.1:9000"
        fi
    else
        PHP_SOCK="unix:$PHP_SOCK"
    fi
    echo -e "Detected PHP Backend: ${CYAN}$PHP_SOCK${PLAIN}"

    # 4. 生成配置文件
    CONF_FILE="$NGINX_CONF_DIR/${SITE_NAME}.conf"
    
    cat > "$CONF_FILE" <<EOF
server {
    listen $PORT;
    server_name $DOMAIN;
    root $WEB_ROOT;
    index index.php index.html;

    # Logs
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

    location ~ /\.ht {
        deny all;
    }
}
EOF
    
    echo -e "${GREEN}Nginx config generated at: $CONF_FILE${PLAIN}"
    
    # 5. 测试并重启
    nginx -t
    if [ $? -eq 0 ]; then
        systemctl restart nginx
        echo -e "${GREEN}Nginx Restarted Successfully!${PLAIN}"
    else
        echo -e "${RED}Nginx Config Error! Please check $CONF_FILE${PLAIN}"
    fi
}

clear
echo -e "${CYAN}=============================================================${PLAIN}"
echo -e "${CYAN}    BitsFlowCloud Looking Glass Installer (Auto-Nginx)${PLAIN}"
echo -e "${CYAN}=============================================================${PLAIN}"
echo -e "1. Install Master (Frontend) [主控端]"
echo -e "2. Install Agent (Node)      [被控端]"
echo -e "${CYAN}=============================================================${PLAIN}"
read -p "Select [1-2]: " install_type

# === 主控端安装 ===
install_master() {
    prepare_env
    fix_php_config

    # 默认目录改为标准 Web 目录
    DEFAULT_DIR="/var/www/html/lg"
    echo -e "\n${YELLOW}--- Installation Path ---${PLAIN}"
    read -p "Enter path (Default: $DEFAULT_DIR): " INSTALL_DIR
    INSTALL_DIR=${INSTALL_DIR:-$DEFAULT_DIR}
    mkdir -p "$INSTALL_DIR"
    
    # 收集配置
    echo -e "\n${YELLOW}--- Site Info ---${PLAIN}"
    read -p "Site Title: " SITE_TITLE
    read -p "Site Header: " SITE_HEADER
    read -p "Footer Text: " FOOTER_TEXT
    read -p "Cloudflare Key (Default: 0x4AAAAAACJhmoIhycq-YD13): " CF_KEY
    CF_KEY=${CF_KEY:-0x4AAAAAACJhmoIhycq-YD13}

    echo -e "\n${YELLOW}--- First Node Info ---${PLAIN}"
    read -p "Node Name: " NODE_NAME
    read -p "Node Country: " NODE_COUNTRY
    read -p "Node IPv4: " NODE_IPV4
    read -p "Node IPv6: " NODE_IPV6
    read -p "Agent URL: " AGENT_URL
    read -p "Agent Key: " AGENT_KEY

    # 下载
    echo -e "\n${GREEN}>>> Downloading files...${PLAIN}"
    wget --no-check-certificate -O "$INSTALL_DIR/index.php" "$URL_INDEX"
    wget --no-check-certificate -O "$INSTALL_DIR/api.php" "$URL_API"
    wget --no-check-certificate -O "$INSTALL_DIR/config.php" "$URL_CONFIG"

    # 替换变量
    sed -i "s#\$siteTitle = .*#\$siteTitle = '$SITE_TITLE';#g" "$INSTALL_DIR/index.php"
    sed -i "s#\$siteHeader = .*#\$siteHeader = '$SITE_HEADER';#g" "$INSTALL_DIR/index.php"
    sed -i "s#\$footerText = .*#\$footerText = '$FOOTER_TEXT';#g" "$INSTALL_DIR/index.php"
    sed -i "s#\$cfSiteKey = .*#\$cfSiteKey = '$CF_KEY';#g" "$INSTALL_DIR/index.php"

    sed -i "s#\$node_name\s*=\s*'';#\$node_name    = '$NODE_NAME';#g" "$INSTALL_DIR/config.php"
    sed -i "s#\$node_country\s*=\s*'';#\$node_country = '$NODE_COUNTRY';#g" "$INSTALL_DIR/config.php"
    sed -i "s#\$node_ipv4\s*=\s*'';#\$node_ipv4    = '$NODE_IPV4';#g" "$INSTALL_DIR/config.php"
    sed -i "s#\$node_ipv6\s*=\s*'';#\$node_ipv6    = '$NODE_IPV6';#g" "$INSTALL_DIR/config.php"
    sed -i "s#\$agent_url\s*=\s*'';#\$agent_url    = '$AGENT_URL';#g" "$INSTALL_DIR/config.php"
    sed -i "s#\$agent_key\s*=\s*'';#\$agent_key    = '$AGENT_KEY';#g" "$INSTALL_DIR/config.php"

    # 权限
    chown -R $WEB_USER:$WEB_USER "$INSTALL_DIR"
    chmod -R 755 "$INSTALL_DIR"

    # 配置 Nginx
    setup_nginx_conf "lg_master" "$INSTALL_DIR"

    echo -e "\n${GREEN}✅ Master Installed! Access via http://$DOMAIN (or IP)${PLAIN}"
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
    read -p "Secret Key: " SECRET_KEY
    read -p "Public IPv4: " PUB_IPV4
    read -p "Public IPv6: " PUB_IPV6

    # 下载
    echo -e "\n${GREEN}>>> Downloading files...${PLAIN}"
    wget --no-check-certificate -O "$INSTALL_DIR/agent.php" "$URL_AGENT"
    wget --no-check-certificate -O "$INSTALL_DIR/check_stream.py" "$URL_CHECK"

    # 替换
    sed -i "s#\$SECRET_KEY\s*=\s*'';#\$SECRET_KEY   = '$SECRET_KEY';#g" "$INSTALL_DIR/agent.php"
    sed -i "s#\$PUBLIC_IP_V4\s*=\s*'';#\$PUBLIC_IP_V4 = '$PUB_IPV4';#g" "$INSTALL_DIR/agent.php"
    sed -i "s#\$PUBLIC_IP_V6\s*=\s*'';#\$PUBLIC_IP_V6 = '$PUB_IPV6';#g" "$INSTALL_DIR/agent.php"

    # 1GB 文件
    echo -e "${GREEN}>>> Generating 1GB test file...${PLAIN}"
    if [ ! -f "$INSTALL_DIR/1gb.bin" ]; then
        dd if=/dev/zero of="$INSTALL_DIR/1gb.bin" bs=1M count=1000 status=progress
    fi

    # 运行检测
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

    # 权限
    chown -R $WEB_USER:$WEB_USER "$INSTALL_DIR"
    chmod -R 755 "$INSTALL_DIR"

    # 配置 Nginx (被控端也需要Web访问)
    setup_nginx_conf "lg_agent" "$INSTALL_DIR"

    echo -e "\n${GREEN}✅ Agent Installed! URL: http://$DOMAIN/agent.php${PLAIN}"
}

case $install_type in
    1) install_master ;;
    2) install_agent ;;
    *) echo -e "${RED}Invalid selection!${PLAIN}" ;;
esac
