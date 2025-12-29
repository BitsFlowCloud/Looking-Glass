#!/bin/bash

# ==============================================================
# BitsFlowCloud Looking Glass Installer (Smart Edition)
# ==============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# === 资源链接 ===
URL_INDEX="https://raw.githubusercontent.com/BitsFlowCloud/Looking-Glass/refs/heads/main/index.php"
URL_API="https://raw.githubusercontent.com/BitsFlowCloud/Looking-Glass/refs/heads/main/api.php"
URL_CONFIG="https://raw.githubusercontent.com/BitsFlowCloud/Looking-Glass/refs/heads/main/config.php"
URL_AGENT="https://raw.githubusercontent.com/BitsFlowCloud/Looking-Glass/refs/heads/main/agent.php"
URL_CHECK="https://raw.githubusercontent.com/BitsFlowCloud/Looking-Glass/refs/heads/main/check_stream.py"
URL_TCP="https://raw.githubusercontent.com/BitsFlowCloud/Looking-Glass/refs/heads/main/tcp.sh"

[[ $EUID -ne 0 ]] && echo -e "${RED}Error: Must be run as root!${PLAIN}" && exit 1

detect_web_user() {
    if id "www" &>/dev/null; then echo "www"; elif id "www-data" &>/dev/null; then echo "www-data"; else echo "root"; fi
}
WEB_USER=$(detect_web_user)

# === 核心函数：检查并安装环境 (不强制覆盖) ===
check_and_install_env() {
    echo -e "${GREEN}>>> Checking Environment...${PLAIN}"
    
    local NEED_INSTALL=0
    
    # 检查 Nginx
    if ! command -v nginx > /dev/null 2>&1; then
        echo -e "${YELLOW}Nginx not found. Marking for installation...${PLAIN}"
        NEED_INSTALL=1
    else
        echo -e "Nginx: ${GREEN}Installed${PLAIN}"
    fi

    # 检查 PHP
    if ! command -v php > /dev/null 2>&1; then
        echo -e "${YELLOW}PHP not found. Marking for installation...${PLAIN}"
        NEED_INSTALL=1
    else
        echo -e "PHP: ${GREEN}Installed${PLAIN}"
    fi

    # 如果需要安装
    if [ $NEED_INSTALL -eq 1 ]; then
        echo -e "${GREEN}>>> Installing missing dependencies...${PLAIN}"
        if [ -f /etc/debian_version ]; then
            apt-get update
            # 安装 Nginx, PHP 及必要扩展
            apt-get install -y nginx php-fpm php-cli php-curl php-json php-mbstring php-xml curl wget unzip
        elif [ -f /etc/redhat-release ]; then
            yum install -y epel-release
            yum install -y nginx php-fpm php-cli php-common php-curl php-json php-mbstring php-xml curl wget unzip
        fi
    fi
}

# === 核心函数：解除 PHP 函数禁用 ===
configure_php() {
    echo -e "${GREEN}>>> Configuring PHP (Removing disabled functions)...${PLAIN}"
    
    # 获取 php.ini 位置
    PHP_INI=$(php --ini | grep "Loaded Configuration File" | awk -F: '{print $2}' | xargs)
    
    if [ -f "$PHP_INI" ]; then
        echo -e "Found php.ini at: $PHP_INI"
        # 依次从 disable_functions 中删除 exec, shell_exec, popen, proc_open
        sed -i 's/exec,//g' "$PHP_INI"
        sed -i 's/shell_exec,//g' "$PHP_INI"
        sed -i 's/popen,//g' "$PHP_INI"
        sed -i 's/proc_open,//g' "$PHP_INI"
        
        # 也可以处理没有逗号的情况
        sed -i 's/exec //g' "$PHP_INI"
        sed -i 's/shell_exec //g' "$PHP_INI"
        sed -i 's/popen //g' "$PHP_INI"
        sed -i 's/proc_open //g' "$PHP_INI"
        
        echo -e "${GREEN}PHP functions enabled.${PLAIN}"
        
        # 重启 PHP-FPM (尝试多种服务名)
        systemctl restart php*-fpm >/dev/null 2>&1 || systemctl restart php-fpm >/dev/null 2>&1
    else
        echo -e "${RED}Warning: Could not locate php.ini. You may need to manually enable exec/popen.${PLAIN}"
    fi
}

clear
echo -e "${CYAN}=============================================================${PLAIN}"
echo -e "${CYAN}    BitsFlowCloud Looking Glass Auto Installer${PLAIN}"
echo -e "${CYAN}=============================================================${PLAIN}"
echo -e "1. Install Master (Frontend) [主控端]"
echo -e "2. Install Agent (Node)      [被控端]"
echo -e "${CYAN}=============================================================${PLAIN}"
read -p "Please select [1-2]: " install_type

# ==============================================================
# 1. 主控端安装逻辑
# ==============================================================
install_master() {
    # 1. 智能安装环境
    check_and_install_env
    # 2. 配置 PHP
    configure_php

    # === 路径 ===
    echo -e "\n${YELLOW}--- Installation Path ---${PLAIN}"
    read -p "Enter path (Default: /root/www/wwwroot/lg): " INSTALL_DIR
    INSTALL_DIR=${INSTALL_DIR:-/root/www/wwwroot/lg}
    mkdir -p "$INSTALL_DIR"
    
    # === 配置 ===
    echo -e "\n${YELLOW}--- Site Configuration ---${PLAIN}"
    read -p "Site Title: " SITE_TITLE
    read -p "Site Header: " SITE_HEADER
    read -p "Footer Text: " FOOTER_TEXT
    read -p "Cloudflare Key (Enter for Default): " CF_KEY
    CF_KEY=${CF_KEY:-0x4AAAAAACJhmoIhycq-YD13}

    echo -e "\n${YELLOW}--- First Node Configuration ---${PLAIN}"
    read -p "Node Name: " NODE_NAME
    read -p "Node Country: " NODE_COUNTRY
    read -p "Node IPv4: " NODE_IPV4
    read -p "Node IPv6: " NODE_IPV6
    read -p "Agent URL: " AGENT_URL
    read -p "Agent Key: " AGENT_KEY

    # === 下载 ===
    echo -e "\n${GREEN}>>> Downloading files...${PLAIN}"
    wget --no-check-certificate -O "$INSTALL_DIR/index.php" "$URL_INDEX"
    wget --no-check-certificate -O "$INSTALL_DIR/api.php" "$URL_API"
    wget --no-check-certificate -O "$INSTALL_DIR/config.php" "$URL_CONFIG"

    # === 替换 ===
    echo -e "${GREEN}>>> Configuring files...${PLAIN}"
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

    # === 权限 ===
    chown -R $WEB_USER:$WEB_USER "$INSTALL_DIR"
    chmod -R 755 "$INSTALL_DIR"

    echo -e "\n${GREEN}✅ Master Installed!${PLAIN}"
    echo -e "Path: $INSTALL_DIR"
    echo -e "Note: Ensure your Nginx root points here."
}

# ==============================================================
# 2. 被控端安装逻辑
# ==============================================================
install_agent() {
    # 1. 智能安装环境 (PHP/Nginx)
    check_and_install_env
    # 2. 配置 PHP (解除禁用函数)
    configure_php
    
    echo -e "${GREEN}>>> Installing Python Dependencies...${PLAIN}"
    if [ -f /etc/debian_version ]; then
        apt-get install -y python3 python3-pip iperf3 mtr-tiny iputils-ping
    elif [ -f /etc/redhat-release ]; then
        yum install -y python3 python3-pip iperf3 mtr ping
    fi
    pip3 install requests

    # === 路径 ===
    echo -e "\n${YELLOW}--- Installation Path ---${PLAIN}"
    read -p "Enter path (Default: /root/www/wwwroot/agent): " INSTALL_DIR
    INSTALL_DIR=${INSTALL_DIR:-/root/www/wwwroot/agent}
    mkdir -p "$INSTALL_DIR"

    # === 配置 ===
    echo -e "\n${YELLOW}--- Agent Configuration ---${PLAIN}"
    read -p "Secret Key: " SECRET_KEY
    read -p "Public IPv4: " PUB_IPV4
    read -p "Public IPv6: " PUB_IPV6

    # === 下载 ===
    echo -e "\n${GREEN}>>> Downloading files...${PLAIN}"
    wget --no-check-certificate -O "$INSTALL_DIR/agent.php" "$URL_AGENT"
    wget --no-check-certificate -O "$INSTALL_DIR/check_stream.py" "$URL_CHECK"

    # === 替换 ===
    echo -e "${GREEN}>>> Configuring Agent...${PLAIN}"
    sed -i "s#\$SECRET_KEY\s*=\s*'';#\$SECRET_KEY   = '$SECRET_KEY';#g" "$INSTALL_DIR/agent.php"
    sed -i "s#\$PUBLIC_IP_V4\s*=\s*'';#\$PUBLIC_IP_V4 = '$PUB_IPV4';#g" "$INSTALL_DIR/agent.php"
    sed -i "s#\$PUBLIC_IP_V6\s*=\s*'';#\$PUBLIC_IP_V6 = '$PUB_IPV6';#g" "$INSTALL_DIR/agent.php"

    # === 测速文件 ===
    echo -e "${GREEN}>>> Generating 1GB test file...${PLAIN}"
    if [ ! -f "$INSTALL_DIR/1gb.bin" ]; then
        dd if=/dev/zero of="$INSTALL_DIR/1gb.bin" bs=1M count=1000 status=progress
    fi

    # === 流媒体检测 ===
    echo -e "${GREEN}>>> Running Stream Check...${PLAIN}"
    chmod +x "$INSTALL_DIR/check_stream.py"
    python3 "$INSTALL_DIR/check_stream.py" --out "$INSTALL_DIR/unlock_result.json"
    
    # === Crontab ===
    echo -e "${GREEN}>>> Setting up Crontab...${PLAIN}"
    CRON_CMD="*/30 * * * * /usr/bin/python3 $INSTALL_DIR/check_stream.py --out $INSTALL_DIR/unlock_result.json >/dev/null 2>&1"
    (crontab -l 2>/dev/null | grep -v "check_stream.py"; echo "$CRON_CMD") | crontab -

    # === 权限 ===
    chown -R $WEB_USER:$WEB_USER "$INSTALL_DIR"
    chmod -R 755 "$INSTALL_DIR"

    # === TCP 优化 ===
    echo -e "\n${GREEN}>>> Running TCP Optimization...${PLAIN}"
    wget --no-check-certificate -O /tmp/tcp.sh "$URL_TCP"
    if [ -f /tmp/tcp.sh ]; then
        chmod +x /tmp/tcp.sh
        bash /tmp/tcp.sh
        rm -f /tmp/tcp.sh
    fi

    echo -e "\n${GREEN}✅ Agent Installed!${PLAIN}"
    echo -e "Path: $INSTALL_DIR"
}

case $install_type in
    1) install_master ;;
    2) install_agent ;;
    *) echo -e "${RED}Invalid selection!${PLAIN}" ;;
esac
