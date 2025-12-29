#!/bin/bash

# ==============================================================
# BitsFlowCloud Looking Glass Installer (v5.0 - Auto Register)
# ==============================================================

# === 颜色定义 ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
PLAIN='\033[0m'
BOLD='\033[1m'

# === 资源链接 ===
REPO_URL="https://raw.githubusercontent.com/BitsFlowCloud/Looking-Glass/refs/heads/main"
URL_INDEX="$REPO_URL/index.php"
URL_API="$REPO_URL/api.php"
URL_AGENT="$REPO_URL/agent.php"
URL_CHECK="$REPO_URL/check_stream.py"
URL_TCP="$REPO_URL/tcp.sh"

# === 检查 Root ===
[[ $EUID -ne 0 ]] && echo -e "${RED}${BOLD}错误：必须使用 root 用户运行此脚本！${PLAIN}" && exit 1

# === 0. 自动获取公网 IP ===
get_public_ips() {
    echo -e "${BLUE}>>> 正在检测服务器 IP...${PLAIN}"
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

    echo -e "IPv4: ${GREEN}$SERVER_IP4${PLAIN}"
    echo -e "IPv6: ${PURPLE}${SERVER_IP6:-无}${PLAIN}"
}

# === 1. 安装基础 Web 环境 ===
install_web_stack() {
    echo -e "${BLUE}>>> 正在安装 Web 环境 (Nginx, PHP, Certbot, Cron)...${PLAIN}"
    if [ -f /etc/debian_version ]; then
        apt-get update -y
        # 增加 cron, ufw 安装
        apt-get install -y nginx php-fpm php-cli php-curl php-json php-mbstring php-xml curl wget unzip python3 python3-pip certbot cron systemd ufw
        WEB_USER="www-data"
        NGINX_CONF_DIR="/etc/nginx/sites-enabled"
        mkdir -p /etc/nginx/sites-enabled
    elif [ -f /etc/redhat-release ]; then
        yum install -y epel-release
        yum install -y nginx php-fpm php-cli php-common php-curl php-json php-mbstring php-xml curl wget unzip python3 python3-pip certbot cronie ufw
        WEB_USER="nginx"
        NGINX_CONF_DIR="/etc/nginx/conf.d"
    else
        echo -e "${RED}不支持的操作系统！${PLAIN}" && exit 1
    fi
    
    # 确保 cron 服务启动
    systemctl enable cron >/dev/null 2>&1 || systemctl enable crond >/dev/null 2>&1
    systemctl start cron >/dev/null 2>&1 || systemctl start crond >/dev/null 2>&1
    
    pip3 install requests --break-system-packages >/dev/null 2>&1 || pip3 install requests >/dev/null 2>&1
    systemctl enable nginx php-fpm >/dev/null 2>&1
    systemctl start nginx php-fpm >/dev/null 2>&1
}

# === 2. 安装网络工具 ===
install_net_tools() {
    echo -e "${BLUE}>>> 正在安装网络工具...${PLAIN}"
    if [ -f /etc/debian_version ]; then
        apt-get install -y iperf3 mtr-tiny iputils-ping traceroute
    elif [ -f /etc/redhat-release ]; then
        yum install -y iperf3 mtr ping traceroute
    fi
    
    # 配置 sudo 权限给 www-data 以运行 mtr
    echo -e "${BLUE}>>> 配置 MTR 权限...${PLAIN}"
    if ! grep -q "$WEB_USER ALL=(ALL) NOPASSWD: /usr/sbin/mtr" /etc/sudoers; then
        echo "$WEB_USER ALL=(ALL) NOPASSWD: /usr/sbin/mtr" >> /etc/sudoers
    fi
    if ! grep -q "$WEB_USER ALL=(ALL) NOPASSWD: /usr/bin/mtr" /etc/sudoers; then
        echo "$WEB_USER ALL=(ALL) NOPASSWD: /usr/bin/mtr" >> /etc/sudoers
    fi
}

# === 3. 修复 PHP 配置 ===
fix_php_config() {
    echo -e "${BLUE}>>> 正在优化 PHP 配置...${PLAIN}"
    PHP_INI=$(php --ini | grep "Loaded Configuration File" | awk -F: '{print $2}' | xargs)
    if [ -f "$PHP_INI" ]; then
        sed -i 's/exec,//g; s/shell_exec,//g; s/popen,//g; s/proc_open,//g' "$PHP_INI"
        sed -i 's/exec //g; s/shell_exec //g; s/popen //g; s/proc_open //g' "$PHP_INI"
        systemctl restart php*-fpm >/dev/null 2>&1 || systemctl restart php-fpm >/dev/null 2>&1
    fi
}

# === 4. 生成 Nginx 配置 ===
setup_nginx_conf() {
    local SITE_NAME=$1
    local WEB_ROOT=$2
    local MODE=$3 

    echo -e "\n${YELLOW}----------------------------------------${PLAIN}"
    echo -e "${YELLOW}       Nginx 配置 ($SITE_NAME)       ${PLAIN}"
    echo -e "${YELLOW}----------------------------------------${PLAIN}"
    
    read -p "请输入域名或 IP (默认: $SERVER_IP4): " DOMAIN
    DOMAIN=${DOMAIN:-$SERVER_IP4}

    if [[ "$DOMAIN" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        IS_IP=true
    else
        IS_IP=false
    fi

    SERVER_NAME_STR="$DOMAIN"
    if [ "$MODE" == "agent" ] && [ -n "$SERVER_IP6" ]; then
        SERVER_NAME_STR="$SERVER_NAME_STR [$SERVER_IP6]"
        echo -e "${GREEN}提示：已自动为被控端添加 IPv6 监听配置。${PLAIN}"
    fi

    PHP_SOCK=$(ls /run/php/php*-fpm.sock 2>/dev/null | head -n 1)
    if [ -z "$PHP_SOCK" ]; then
        if [ -S /run/php-fpm/www.sock ]; then PHP_SOCK="unix:/run/php-fpm/www.sock"; else PHP_SOCK="127.0.0.1:9000"; fi
    else
        PHP_SOCK="unix:$PHP_SOCK"
    fi

    CONF_FILE="$NGINX_CONF_DIR/${SITE_NAME}.conf"
    SSL_ENABLED=false
    CERT_PATH=""
    KEY_PATH=""

    if [ "$IS_IP" = false ]; then
        echo -e "\n${CYAN}检测到域名: $DOMAIN${PLAIN}"
        read -p "您已有 SSL 证书吗？[y/N]: " HAVE_CERT
        
        if [[ "$HAVE_CERT" =~ ^[Yy]$ ]]; then
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
            read -p "您想申请免费的 Let's Encrypt 证书吗？[y/N]: " WANT_LE
            if [[ "$WANT_LE" =~ ^[Yy]$ ]]; then
                echo -e "\n${RED}!!! 重要提示 !!!${PLAIN}"
                echo -e "1. 请确保域名 ${CYAN}$DOMAIN${PLAIN} 的 A 记录已指向 ${CYAN}$SERVER_IP4${PLAIN}。"
                echo -e "2. 请勿开启 CDN (DNS Only)。"
                read -p "按回车键继续..."

                systemctl stop nginx
                echo -e "${GREEN}>>> 正在运行 Certbot...${PLAIN}"
                certbot certonly --standalone -d "$DOMAIN" --email "admin@$DOMAIN" --agree-tos --non-interactive

                if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
                    CERT_PATH="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
                    KEY_PATH="/etc/letsencrypt/live/$DOMAIN/privkey.pem"
                    SSL_ENABLED=true
                    echo -e "${GREEN}SSL 证书申请成功！${PLAIN}"
                    (crontab -l 2>/dev/null | grep -v "certbot renew"; echo "0 3 * * * certbot renew --quiet --deploy-hook 'systemctl reload nginx'") | crontab -
                else
                    echo -e "${RED}SSL 申请失败！将回退到 HTTP 模式。${PLAIN}"
                    SSL_ENABLED=false
                fi
            fi
        fi
    fi

    if [ "$SSL_ENABLED" = true ]; then
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
    echo -e "${GREEN}Nginx 配置完成！${PLAIN}"
}

# === 5. 节点管理工具 ===
manage_nodes() {
    # 查找 config.php
    if [ -f "/var/www/html/lg/config.php" ]; then
        CONFIG_FILE="/var/www/html/lg/config.php"
    else
        read -p "请输入 config.php 文件路径 (默认: /var/www/html/lg/config.php): " CONFIG_FILE
        CONFIG_FILE=${CONFIG_FILE:-"/var/www/html/lg/config.php"}
    fi

    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}错误：找不到配置文件！请确认您是在主控端运行此功能。${PLAIN}"
        exit 1
    fi

    echo -e "\n${PURPLE}=== 节点管理 ===${PLAIN}"
    echo -e "${GREEN}1.${PLAIN} 添加新节点"
    echo -e "${GREEN}2.${PLAIN} 删除节点"
    echo -e "${GREEN}3.${PLAIN} 查看当前节点"
    read -p "请选择 [1-3]: " action

    case $action in
        1)
            echo -e "\n${YELLOW}--- 添加新节点 ---${PLAIN}"
            read -p "节点名称 (如 Tokyo): " N_NAME
            read -p "地区代码 (如 JP): " N_COUNTRY
            read -p "节点 IPv4 (用于展示): " N_IPV4
            read -p "节点 IPv6 (可选): " N_IPV6
            read -p "被控端 URL (如 http://1.2.3.4/agent.php): " N_URL
            read -p "通讯密钥: " N_KEY
            
            php -r "
                \$c = include '$CONFIG_FILE';
                if (!is_array(\$c)) die('Config file damaged');
                \$c['nodes'][] = [
                    'name' => '$N_NAME',
                    'country' => '$N_COUNTRY',
                    'ipv4' => '$N_IPV4',
                    'ipv6' => '$N_IPV6',
                    'api_url' => '$N_URL',
                    'key' => '$N_KEY'
                ];
                file_put_contents('$CONFIG_FILE', '<?php' . PHP_EOL . 'return ' . var_export(\$c, true) . ';');
            "
            echo -e "${GREEN}✅ 节点已添加！${PLAIN}"
            ;;
        2)
            echo -e "\n${YELLOW}--- 删除节点 ---${PLAIN}"
            php -r "
                \$c = include '$CONFIG_FILE';
                foreach(\$c['nodes'] as \$k => \$v) {
                    echo \"ID: \$k | Name: {\$v['name']} | IP: {\$v['ipv4']}\n\";
                }
            "
            read -p "请输入要删除的节点 ID: " DEL_ID
            
            php -r "
                \$c = include '$CONFIG_FILE';
                if (isset(\$c['nodes'][$DEL_ID])) {
                    unset(\$c['nodes'][$DEL_ID]);
                    file_put_contents('$CONFIG_FILE', '<?php' . PHP_EOL . 'return ' . var_export(\$c, true) . ';');
                    echo 'Deleted.';
                } else {
                    echo 'ID not found.';
                }
            "
            echo -e "\n${GREEN}✅ 操作完成！${PLAIN}"
            ;;
        3)
            echo -e "\n${YELLOW}--- 当前节点列表 ---${PLAIN}"
            php -r "
                \$c = include '$CONFIG_FILE';
                foreach(\$c['nodes'] as \$k => \$v) {
                    echo \"ID: \$k | Name: {\$v['name']} | URL: {\$v['api_url']}\n\";
                }
            "
            ;;
        *) echo -e "${RED}无效选项${PLAIN}" ;;
    esac
}

# === 界面绘制 ===
clear
echo -e "${CYAN}=============================================================${PLAIN}"
echo -e "${PURPLE}${BOLD}      BitsFlowCloud Looking Glass Installer v5.0${PLAIN}"
echo -e "${CYAN}=============================================================${PLAIN}"
echo -e "${GREEN}1.${PLAIN} 安装 ${BOLD}主控端 (Master)${PLAIN} - 网站前端"
echo -e "${GREEN}2.${PLAIN} 安装 ${BOLD}被控端 (Agent)${PLAIN}  - 节点服务器"
echo -e "${GREEN}3.${PLAIN} 管理节点 (添加/删除/查看) [仅限主控端]"
echo -e "${CYAN}=============================================================${PLAIN}"
read -p "请选择 [1-3]: " install_type

# 初始化 IP (仅安装模式需要)
if [ "$install_type" == "1" ] || [ "$install_type" == "2" ]; then
    get_public_ips
fi

# === 主控端安装 ===
install_master() {
    install_web_stack 
    fix_php_config

    DEFAULT_DIR="/var/www/html/lg"
    echo -e "\n${YELLOW}----------------------------------------${PLAIN}"
    echo -e "${YELLOW}           主控端安装向导           ${PLAIN}"
    echo -e "${YELLOW}----------------------------------------${PLAIN}"
    read -p "请输入安装路径 (默认: $DEFAULT_DIR): " INSTALL_DIR
    INSTALL_DIR=${INSTALL_DIR:-$DEFAULT_DIR}
    mkdir -p "$INSTALL_DIR"
    
    echo -e "\n${BLUE}--- 站点基本信息 ---${PLAIN}"
    read -p "网站标题 (Title): " SITE_TITLE
    read -p "顶部大标题 (Header): " SITE_HEADER
    read -p "页脚文本 (Footer): " FOOTER_TEXT

    # === Cloudflare 配置 ===
    echo -e "\n${BLUE}--- 安全设置 (Cloudflare Turnstile) ---${PLAIN}"
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

    # === 新增：配置自动注册令牌 ===
    echo -e "\n${BLUE}--- 节点自动注册设置 ---${PLAIN}"
    read -p "请设置一个节点注册令牌 (Registration Token): " REG_TOKEN
    [ -z "$REG_TOKEN" ] && REG_TOKEN="BitsFlowCloud-$(date +%s)"
    echo -e "已设置令牌: ${CYAN}$REG_TOKEN${PLAIN}"

    # === 下载文件 ===
    echo -e "\n${GREEN}>>> 正在下载主控端文件...${PLAIN}"
    wget --no-check-certificate -O "$INSTALL_DIR/index.php" "$URL_INDEX"
    wget --no-check-certificate -O "$INSTALL_DIR/api.php" "$URL_API"

    # === 生成 Config.php (空节点列表) ===
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

    // Auto Registration Token
    'node_registration_token' => '$REG_TOKEN',

    // Nodes List (Initially Empty)
    'nodes' => []
];
EOF

    # === 关键权限设置 (允许 API 修改) ===
    chown -R $WEB_USER:$WEB_USER "$INSTALL_DIR"
    chmod -R 755 "$INSTALL_DIR"
    chmod 666 "$INSTALL_DIR/config.php"

    setup_nginx_conf "lg_master" "$INSTALL_DIR" "master"

    echo -e "\n${GREEN}✅ 主控端安装完成！${PLAIN}"
    echo -e "访问地址: http://$DOMAIN"
    echo -e "节点注册令牌: ${CYAN}$REG_TOKEN${PLAIN} (请妥善保存，用于添加新节点)"
}

# === 被控端安装 ===
install_agent() {
    install_web_stack 
    install_net_tools 
    fix_php_config
    
    DEFAULT_DIR="/var/www/html/agent"
    echo -e "\n${YELLOW}----------------------------------------${PLAIN}"
    echo -e "${YELLOW}           被控端安装向导           ${PLAIN}"
    echo -e "${YELLOW}----------------------------------------${PLAIN}"
    read -p "请输入安装路径 (默认: $DEFAULT_DIR): " INSTALL_DIR
    INSTALL_DIR=${INSTALL_DIR:-$DEFAULT_DIR}
    mkdir -p "$INSTALL_DIR"

    echo -e "\n${BLUE}--- 被控端信息 ---${PLAIN}"
    read -p "通讯密钥 (必须与主控端一致): " SECRET_KEY
    
    # === 新增：收集注册信息 ===
    read -p "节点名称 (如 Tokyo): " MY_NAME
    read -p "地区代码 (如 JP): " MY_COUNTRY
    
    read -p "公网 IPv4 (默认: $SERVER_IP4): " PUB_IPV4
    PUB_IPV4=${PUB_IPV4:-$SERVER_IP4}
    
    read -p "公网 IPv6 (默认: ${SERVER_IP6:-无}): " PUB_IPV6
    PUB_IPV6=${PUB_IPV6:-$SERVER_IP6}

    echo -e "\n${GREEN}>>> 正在下载被控端文件...${PLAIN}"
    wget --no-check-certificate -O "$INSTALL_DIR/agent.php" "$URL_AGENT"
    wget --no-check-certificate -O "$INSTALL_DIR/check_stream.py" "$URL_CHECK"

    sed -i "s#\$SECRET_KEY\s*=\s*'';#\$SECRET_KEY   = '$SECRET_KEY';#g" "$INSTALL_DIR/agent.php"
    sed -i "s#\$PUBLIC_IP_V4\s*=\s*'';#\$PUBLIC_IP_V4 = '$PUB_IPV4';#g" "$INSTALL_DIR/agent.php"
    sed -i "s#\$PUBLIC_IP_V6\s*=\s*'';#\$PUBLIC_IP_V6 = '$PUB_IPV6';#g" "$INSTALL_DIR/agent.php"

    echo -e "${GREEN}>>> 正在生成 1GB 测速文件...${PLAIN}"
    if [ ! -f "$INSTALL_DIR/1gb.bin" ]; then
        dd if=/dev/zero of="$INSTALL_DIR/1gb.bin" bs=1M count=1000 status=progress
    fi

    echo -e "${GREEN}>>> 配置流媒体检测任务...${PLAIN}"
    chmod +x "$INSTALL_DIR/check_stream.py"
    chown $WEB_USER:$WEB_USER "$INSTALL_DIR/check_stream.py"
    CRON_CMD="*/30 * * * * /usr/bin/python3 $INSTALL_DIR/check_stream.py --out $INSTALL_DIR/unlock_result.json >/dev/null 2>&1"
    (crontab -l 2>/dev/null | grep -v "check_stream.py"; echo "$CRON_CMD") | crontab -
    nohup python3 "$INSTALL_DIR/check_stream.py" --out "$INSTALL_DIR/unlock_result.json" >/dev/null 2>&1 &

    echo -e "\n${GREEN}>>> 正在运行 TCP 优化脚本...${PLAIN}"
    wget --no-check-certificate -O /tmp/tcp.sh "$URL_TCP"
    [ -f /tmp/tcp.sh ] && bash /tmp/tcp.sh && rm -f /tmp/tcp.sh

    # === UFW 防火墙配置 ===
    echo -e "\n${BLUE}>>> 配置防火墙 (UFW)...${PLAIN}"
    if [ -f /etc/debian_version ]; then
        apt-get install -y ufw
    elif [ -f /etc/redhat-release ]; then
        yum install -y epel-release
        yum install -y ufw
    fi

    if command -v ufw >/dev/null 2>&1; then
        ufw allow 22/tcp comment 'SSH'
        ufw allow 80/tcp comment 'HTTP'
        ufw allow 443/tcp comment 'HTTPS'
        ufw allow 30000:40000/tcp comment 'Iperf3 Range'
        # 强制开启
        echo "y" | ufw enable
        echo -e "${GREEN}防火墙已开启并放行端口: 22, 80, 443, 30000-40000${PLAIN}"
    else
        echo -e "${RED}UFW 安装失败，请手动配置防火墙放行端口 30000-40000${PLAIN}"
    fi

    chown -R $WEB_USER:$WEB_USER "$INSTALL_DIR"
    chmod -R 755 "$INSTALL_DIR"

    setup_nginx_conf "lg_agent" "$INSTALL_DIR" "agent"

    echo -e "\n${GREEN}✅ 被控端安装完成！${PLAIN}"
    MY_URL="http://$DOMAIN/agent.php"
    echo -e "Agent URL: $MY_URL"

    # === 新增：自动上报逻辑 ===
    echo -e "\n${CYAN}--- 自动注册到主控端 ---${PLAIN}"
    read -p "是否立即上报到主控端? [y/N]: " DO_REPORT
    if [[ "$DO_REPORT" =~ ^[Yy]$ ]]; then
        read -p "主控端 API 地址 (如 http://master.com/api.php): " MASTER_API
        read -p "注册令牌 (Registration Token): " REG_TOKEN
        
        echo -e "${BLUE}>>> 正在发送注册请求...${PLAIN}"
        RESPONSE=$(curl -s -X POST \
            -d "action=add_node" \
            -d "reg_token=$REG_TOKEN" \
            -d "name=$MY_NAME" \
            -d "country=$MY_COUNTRY" \
            -d "ipv4=$PUB_IPV4" \
            -d "ipv6=$PUB_IPV6" \
            -d "api_url=$MY_URL" \
            -d "key=$SECRET_KEY" \
            "$MASTER_API")
        
        # 简单判断返回内容是否包含 success
        if [[ "$RESPONSE" == *"success"* ]]; then
            echo -e "${GREEN}🎉 注册成功！节点已添加。${PLAIN}"
        else
            echo -e "${RED}❌ 注册失败。主控端返回: $RESPONSE${PLAIN}"
        fi
    fi
}

case $install_type in
    1) install_master ;;
    2) install_agent ;;
    3) manage_nodes ;;
    *) echo -e "${RED}无效的选择！${PLAIN}" ;;
esac
