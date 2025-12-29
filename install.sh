#!/bin/bash

# ==============================================================
# BitsFlowCloud Looking Glass Installer (v3.1 - 中文版)
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

[[ $EUID -ne 0 ]] && echo -e "${RED}错误：必须使用 root 用户运行此脚本！${PLAIN}" && exit 1

# === 0. 自动获取公网 IP ===
get_public_ips() {
    echo -e "${GREEN}>>> 正在检测服务器 IP...${PLAIN}"
    # IPv4
    SERVER_IP4=$(curl -sL -4 --max-time 3 http://ipv4.icanhazip.com | tr -d '\n')
    if [[ "$SERVER_IP4" != *.* ]] || [[ "$SERVER_IP4" == *"html"* ]]; then
        SERVER_IP4=$(curl -sL -4 --max-time 3 --user-agent "Mozilla/5.0" http://ip.sb | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
    fi
    [ -z "$SERVER_IP4" ] && SERVER_IP4="127.0.0.1"
    
    # IPv6
    SERVER_IP6=$(curl -sL -6 --max-time 3 http://ipv6.icanhazip.com | tr -d '\n')
    if [[ "$SERVER_IP6" != *:* ]] || [[ ${#SERVER_IP6} -lt 5 ]]; then
        SERVER_IP6=$(curl -sL -6 --max-time 3 http://ifconfig.co | tr -d '\n')
    fi
    if [[ "$SERVER_IP6" != *:* ]] || [[ ${#SERVER_IP6} -lt 5 ]]; then
        SERVER_IP6=""
    fi

    echo -e "IPv4: ${CYAN}$SERVER_IP4${PLAIN}"
    echo -e "IPv6: ${CYAN}${SERVER_IP6:-无}${PLAIN}"
}

# === 1. 安装基础 Web 环境 (增加 Certbot) ===
install_web_stack() {
    echo -e "${GREEN}>>> 正在安装 Web 环境 (Nginx, PHP, Certbot)...${PLAIN}"
    if [ -f /etc/debian_version ]; then
        apt-get update
        apt-get install -y nginx php-fpm php-cli php-curl php-json php-mbstring php-xml curl wget unzip python3 python3-pip certbot
        WEB_USER="www-data"
        NGINX_CONF_DIR="/etc/nginx/sites-enabled"
        mkdir -p /etc/nginx/sites-enabled
    elif [ -f /etc/redhat-release ]; then
        yum install -y epel-release
        yum install -y nginx php-fpm php-cli php-common php-curl php-json php-mbstring php-xml curl wget unzip python3 python3-pip certbot
        WEB_USER="nginx"
        NGINX_CONF_DIR="/etc/nginx/conf.d"
    else
        echo -e "${RED}不支持的操作系统！${PLAIN}" && exit 1
    fi
    
    pip3 install requests >/dev/null 2>&1
    systemctl enable nginx php-fpm >/dev/null 2>&1
    systemctl start nginx php-fpm >/dev/null 2>&1
}

# === 2. 安装网络工具 (仅被控端) ===
install_net_tools() {
    echo -e "${GREEN}>>> 正在安装网络工具 (Iperf3, MTR, Ping)...${PLAIN}"
    if [ -f /etc/debian_version ]; then
        apt-get install -y iperf3 mtr-tiny iputils-ping
    elif [ -f /etc/redhat-release ]; then
        yum install -y iperf3 mtr ping
    fi
}

# === 3. 修复 PHP 配置 ===
fix_php_config() {
    echo -e "${GREEN}>>> 正在配置 PHP...${PLAIN}"
    PHP_INI=$(php --ini | grep "Loaded Configuration File" | awk -F: '{print $2}' | xargs)
    if [ -f "$PHP_INI" ]; then
        sed -i 's/exec,//g; s/shell_exec,//g; s/popen,//g; s/proc_open,//g' "$PHP_INI"
        sed -i 's/exec //g; s/shell_exec //g; s/popen //g; s/proc_open //g' "$PHP_INI"
        systemctl restart php*-fpm >/dev/null 2>&1 || systemctl restart php-fpm >/dev/null 2>&1
    fi
}

# === 4. 生成 Nginx 配置 (含 SSL 逻辑) ===
setup_nginx_conf() {
    local SITE_NAME=$1
    local WEB_ROOT=$2
    local MODE=$3  # master 或 agent

    echo -e "\n${YELLOW}--- Nginx 配置 ($SITE_NAME) ---${PLAIN}"
    
    # 询问域名或IP
    read -p "请输入域名或 IP (默认: $SERVER_IP4): " DOMAIN
    DOMAIN=${DOMAIN:-$SERVER_IP4}

    # 判断是否为 IP 地址
    if [[ "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        IS_IP=true
    else
        IS_IP=false
    fi

    # === Server Name 构造 ===
    SERVER_NAME_STR="$DOMAIN"
    if [ "$MODE" == "agent" ] && [ -n "$SERVER_IP6" ]; then
        SERVER_NAME_STR="$SERVER_NAME_STR [$SERVER_IP6]"
        echo -e "${GREEN}提示：已自动为被控端添加 IPv6 监听配置。${PLAIN}"
    fi

    # PHP Socket
    PHP_SOCK=$(ls /run/php/php*-fpm.sock 2>/dev/null | head -n 1)
    if [ -z "$PHP_SOCK" ]; then
        if [ -S /run/php-fpm/www.sock ]; then PHP_SOCK="unix:/run/php-fpm/www.sock"; else PHP_SOCK="127.0.0.1:9000"; fi
    else
        PHP_SOCK="unix:$PHP_SOCK"
    fi
    echo -e "检测到 PHP 后端: ${CYAN}$PHP_SOCK${PLAIN}"

    CONF_FILE="$NGINX_CONF_DIR/${SITE_NAME}.conf"
    SSL_ENABLED=false
    CERT_PATH=""
    KEY_PATH=""

    # === SSL 流程 ===
    if [ "$IS_IP" = false ]; then
        echo -e "\n${CYAN}检测到域名: $DOMAIN${PLAIN}"
        read -p "您已有 SSL 证书吗？[y/N]: " HAVE_CERT
        
        if [[ "$HAVE_CERT" =~ ^[Yy]$ ]]; then
            # --- 手动输入证书 ---
            mkdir -p /etc/nginx/ssl
            echo -e "${YELLOW}请粘贴您的 证书内容 (CRT/PEM)，按回车后按 Ctrl+D 保存:${PLAIN}"
            cat > "/etc/nginx/ssl/$DOMAIN.crt"
            echo -e "${YELLOW}请粘贴您的 私钥内容 (KEY)，按回车后按 Ctrl+D 保存:${PLAIN}"
            cat > "/etc/nginx/ssl/$DOMAIN.key"
            
            CERT_PATH="/etc/nginx/ssl/$DOMAIN.crt"
            KEY_PATH="/etc/nginx/ssl/$DOMAIN.key"
            SSL_ENABLED=true
            echo -e "${GREEN}证书已保存。${PLAIN}"

        else
            # --- Let's Encrypt 自动申请 ---
            read -p "您想申请免费的 Let's Encrypt 证书吗？[y/N]: " WANT_LE
            if [[ "$WANT_LE" =~ ^[Yy]$ ]]; then
                echo -e "\n${RED}!!! 重要提示 !!!${PLAIN}"
                echo -e "1. 请确保域名 ${CYAN}$DOMAIN${PLAIN} 的 A 记录已指向 ${CYAN}$SERVER_IP4${PLAIN}。"
                echo -e "2. 请勿开启 CDN (如 Cloudflare 小云朵)，必须使用 DNS Only 模式。"
                echo -e "3. 将占用 80 端口进行验证。"
                read -p "按回车键继续..."

                # 停止 Nginx 释放 80 端口
                systemctl stop nginx
                
                # 申请证书
                echo -e "${GREEN}>>> 正在运行 Certbot 申请证书...${PLAIN}"
                certbot certonly --standalone -d "$DOMAIN" --email "admin@$DOMAIN" --agree-tos --non-interactive

                if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
                    CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
                    KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
                    SSL_ENABLED=true
                    echo -e "${GREEN}SSL 证书申请成功！${PLAIN}"
                    
                    # 添加自动续签任务
                    (crontab -l 2>/dev/null | grep -v "certbot renew"; echo "0 3 * * * certbot renew --quiet --deploy-hook 'systemctl reload nginx'") | crontab -
                else
                    echo -e "${RED}SSL 申请失败！将回退到 HTTP 模式。${PLAIN}"
                    SSL_ENABLED=false
                fi
            fi
        fi
    fi

    # === 生成 Nginx 配置文件 ===
    if [ "$SSL_ENABLED" = true ]; then
        # >>> HTTPS 配置 <<<
        cat > "$CONF_FILE" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $SERVER_NAME_STR;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $SERVER_NAME_STR;
    root $WEB_ROOT;
    index index.php index.html;

    ssl_certificate $CERT_PATH;
    ssl_certificate_key $KEY_PATH;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

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
    else
        # >>> HTTP 配置 (IP模式 或 SSL失败) <<<
        cat > "$CONF_FILE" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $SERVER_NAME_STR;
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
    fi
    
    nginx -t && systemctl restart nginx
    echo -e "${GREEN}Nginx 配置完成并已重启！${PLAIN}"
    
    if [ "$SSL_ENABLED" = true ]; then
        echo -e "${GREEN}站点地址: https://$DOMAIN${PLAIN}"
    else
        echo -e "${GREEN}站点地址: http://$DOMAIN${PLAIN}"
    fi
}

clear
echo -e "${CYAN}=============================================================${PLAIN}"
echo -e "${CYAN}    BitsFlowCloud Looking Glass 安装脚本 (v3.1 - 中文版)${PLAIN}"
echo -e "${CYAN}=============================================================${PLAIN}"
echo -e "1. 安装主控端 (前端)"
echo -e "2. 安装被控端 (节点)"
echo -e "${CYAN}=============================================================${PLAIN}"
read -p "请选择 [1-2]: " install_type

# 初始化 IP
get_public_ips

# === 主控端安装 ===
install_master() {
    install_web_stack 
    fix_php_config

    DEFAULT_DIR="/var/www/html/lg"
    echo -e "\n${YELLOW}--- 安装路径 ---${PLAIN}"
    read -p "请输入路径 (默认: $DEFAULT_DIR): " INSTALL_DIR
    INSTALL_DIR=${INSTALL_DIR:-$DEFAULT_DIR}
    mkdir -p "$INSTALL_DIR"
    
    echo -e "\n${YELLOW}--- 站点信息 ---${PLAIN}"
    read -p "网站标题: " SITE_TITLE
    read -p "网站顶部大标题: " SITE_HEADER
    read -p "页脚文本: " FOOTER_TEXT

    # === Cloudflare 配置 ===
    echo -e "\n${YELLOW}--- 安全设置 (Cloudflare Turnstile 人机验证) ---${PLAIN}"
    read -p "是否启用 Cloudflare Turnstile? [y/N]: " ENABLE_CF
    if [[ "$ENABLE_CF" =~ ^[Yy]$ ]]; then
        CF_BOOL="true"
        read -p "请输入 Site Key: " CF_SITE_KEY
        read -p "请输入 Secret Key: " CF_SECRET_KEY
    else
        CF_BOOL="false"
        CF_SITE_KEY=""
        CF_SECRET_KEY=""
        echo -e "${YELLOW}已禁用人机验证。${PLAIN}"
    fi

    # === 节点 1 配置 ===
    echo -e "\n${YELLOW}--- 首个节点配置 ---${PLAIN}"
    read -p "节点名称 (如 Hong Kong): " NODE_NAME
    read -p "节点地区代码 (如 HK): " NODE_COUNTRY
    
    read -p "节点 IPv4 (默认: $SERVER_IP4): " NODE_IPV4
    NODE_IPV4=${NODE_IPV4:-$SERVER_IP4}
    
    read -p "节点 IPv6 (默认: ${SERVER_IP6:-无}): " NODE_IPV6
    NODE_IPV6=${NODE_IPV6:-$SERVER_IP6}
    
    read -p "被控端 URL (如 http://$NODE_IPV4/agent.php): " AGENT_URL
    [ -z "$AGENT_URL" ] && AGENT_URL="http://$NODE_IPV4/agent.php"
    
    read -p "通讯密钥 (Secret Key): " AGENT_KEY

    # === 下载文件 ===
    echo -e "\n${GREEN}>>> 正在下载文件...${PLAIN}"
    wget --no-check-certificate -O "$INSTALL_DIR/index.php" "$URL_INDEX"
    wget --no-check-certificate -O "$INSTALL_DIR/api.php" "$URL_API"

    # === 生成 Config.php ===
    echo -e "${GREEN}>>> 正在生成 config.php...${PLAIN}"
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

    # 传入 "master" 模式
    setup_nginx_conf "lg_master" "$INSTALL_DIR" "master"

    echo -e "\n${GREEN}✅ 主控端安装完成！${PLAIN}"
}

# === 被控端安装 ===
install_agent() {
    install_web_stack 
    install_net_tools 
    fix_php_config
    
    DEFAULT_DIR="/var/www/html/agent"
    echo -e "\n${YELLOW}--- 安装路径 ---${PLAIN}"
    read -p "请输入路径 (默认: $DEFAULT_DIR): " INSTALL_DIR
    INSTALL_DIR=${INSTALL_DIR:-$DEFAULT_DIR}
    mkdir -p "$INSTALL_DIR"

    echo -e "\n${YELLOW}--- 被控端信息 ---${PLAIN}"
    read -p "通讯密钥 (必须与主控端一致): " SECRET_KEY
    
    read -p "公网 IPv4 (默认: $SERVER_IP4): " PUB_IPV4
    PUB_IPV4=${PUB_IPV4:-$SERVER_IP4}
    
    read -p "公网 IPv6 (默认: ${SERVER_IP6:-无}): " PUB_IPV6
    PUB_IPV6=${PUB_IPV6:-$SERVER_IP6}

    echo -e "\n${GREEN}>>> 正在下载文件...${PLAIN}"
    wget --no-check-certificate -O "$INSTALL_DIR/agent.php" "$URL_AGENT"
    wget --no-check-certificate -O "$INSTALL_DIR/check_stream.py" "$URL_CHECK"

    sed -i "s#\$SECRET_KEY\s*=\s*'';#\$SECRET_KEY   = '$SECRET_KEY';#g" "$INSTALL_DIR/agent.php"
    sed -i "s#\$PUBLIC_IP_V4\s*=\s*'';#\$PUBLIC_IP_V4 = '$PUB_IPV4';#g" "$INSTALL_DIR/agent.php"
    sed -i "s#\$PUBLIC_IP_V6\s*=\s*'';#\$PUBLIC_IP_V6 = '$PUB_IPV6';#g" "$INSTALL_DIR/agent.php"

    echo -e "${GREEN}>>> 正在生成 1GB 测试文件...${PLAIN}"
    if [ ! -f "$INSTALL_DIR/1gb.bin" ]; then
        dd if=/dev/zero of="$INSTALL_DIR/1gb.bin" bs=1M count=1000 status=progress
    fi

    echo -e "${GREEN}>>> 正在运行流媒体解锁检测...${PLAIN}"
    chmod +x "$INSTALL_DIR/check_stream.py"
    python3 "$INSTALL_DIR/check_stream.py" --out "$INSTALL_DIR/unlock_result.json"
    
    CRON_CMD="*/30 * * * * /usr/bin/python3 $INSTALL_DIR/check_stream.py --out $INSTALL_DIR/unlock_result.json >/dev/null 2>&1"
    (crontab -l 2>/dev/null | grep -v "check_stream.py"; echo "$CRON_CMD") | crontab -

    echo -e "\n${GREEN}>>> 正在运行 TCP 优化脚本...${PLAIN}"
    wget --no-check-certificate -O /tmp/tcp.sh "$URL_TCP"
    [ -f /tmp/tcp.sh ] && bash /tmp/tcp.sh && rm -f /tmp/tcp.sh

    chown -R $WEB_USER:$WEB_USER "$INSTALL_DIR"
    chmod -R 755 "$INSTALL_DIR"

    # 传入 "agent" 模式
    setup_nginx_conf "lg_agent" "$INSTALL_DIR" "agent"

    echo -e "\n${GREEN}✅ 被控端安装完成！${PLAIN}"
}

case $install_type in
    1) install_master ;;
    2) install_agent ;;
    *) echo -e "${RED}无效的选择！${PLAIN}" ;;
esac
