#!/bin/bash

# 定义颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# ==========================================
# 默认配置
# ==========================================
DEFAULT_DIR="/root/www/wwwroot/lg-master"
DEFAULT_TITLE="My Looking Glass"
# 为了配合 Nginx 反代，建议 PHP 跑在本地高位端口
DEFAULT_PORT=8080

# 配置文件路径
SETTINGS_FILE="/root/.lg_master_settings"
PID_FILE="/tmp/lg-master.pid"
LOG_FILE="/tmp/lg-master.log"

echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}   BitsFlowCloud Looking Glass - 主控端 (SSL版) ${NC}"
echo -e "${GREEN}=============================================${NC}"

# ==========================================
# 0. 环境检查
# ==========================================
function check_env() {
    if [[ $EUID -ne 0 ]]; then
       echo -e "${RED}错误: 请使用 root 用户运行此脚本。${NC}"
       exit 1
    fi

    # 检查 PHP
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
# 1. 交互式配置向导
# ==========================================
function configure_install() {
    echo -e "${YELLOW}>>> 进入配置向导${NC}"

    # 1. 安装目录
    read -p "1. 安装目录 [$DEFAULT_DIR]: " INPUT_DIR
    WEB_ROOT=${INPUT_DIR:-$DEFAULT_DIR}

    # 2. 网站标题
    read -p "2. 网站标题 [$DEFAULT_TITLE]: " INPUT_TITLE
    SITE_TITLE=${INPUT_TITLE:-$DEFAULT_TITLE}

    # 3. Cloudflare Turnstile Site Key
    echo -e "   -------------------------------------------------------"
    echo -e "   请前往 https://dash.cloudflare.com/ 申请 Turnstile 验证"
    echo -e "   注意: 这里只需要填写公开的 [Site Key]"
    echo -e "   -------------------------------------------------------"
    while true; do
        read -p "3. 请输入 CF Turnstile Site Key: " INPUT_CF
        if [ -n "$INPUT_CF" ]; then
            CF_SITE_KEY="$INPUT_CF"
            break
        else
            echo -e "${RED}错误: Site Key 不能为空。${NC}"
        fi
    done

    # 4. 运行端口
    echo -e "   注意: 如果您打算启用 SSL，这里请保持默认 8080 (作为后端端口)"
    read -p "4. PHP后端运行端口 [$DEFAULT_PORT]: " INPUT_PORT
    SERVER_PORT=${INPUT_PORT:-$DEFAULT_PORT}

    # 保存配置
    echo "WEB_ROOT=\"$WEB_ROOT\"" > "$SETTINGS_FILE"
    echo "SERVER_PORT=\"$SERVER_PORT\"" >> "$SETTINGS_FILE"
    echo "SITE_TITLE=\"$SITE_TITLE\"" >> "$SETTINGS_FILE"
    echo "CF_SITE_KEY=\"$CF_SITE_KEY\"" >> "$SETTINGS_FILE"
    
    echo -e "${GREEN}配置已保存！${NC}"
}

# ==========================================
# 2. 核心文件部署
# ==========================================
function install_files() {
    if [ ! -f "$SETTINGS_FILE" ]; then configure_install; fi
    source "$SETTINGS_FILE"

    if [ ! -d "$WEB_ROOT" ]; then mkdir -p "$WEB_ROOT"; fi

    echo -e "${YELLOW}正在生成文件...${NC}"

    # --- 生成 config.php ---
    CONFIG_FILE="$WEB_ROOT/config.php"
    if [ ! -f "$CONFIG_FILE" ]; then
        cat << EOF > "$CONFIG_FILE"
<?php
return [
    'site_title' => '$SITE_TITLE',
    'nodes' => [
        //_NEXT_NODE_
    ]
];
EOF
    else
        sed -i "s/'site_title' => .*/'site_title' => '$SITE_TITLE',/" "$CONFIG_FILE"
    fi

    # --- 生成 index.php ---
    cat << EOF > "$WEB_ROOT/index.php"
<?php \$config = require 'config.php'; ?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php echo \$config['site_title']; ?></title>
    <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;700&family=Share+Tech+Mono&display=swap" rel="stylesheet">
    <script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script>
    <style>
        :root { --cyan: #00f3ff; --purple: #bc13fe; --green: #00ff9d; --pink: #ff00de; --yellow: #f1c40f; --bg-color: #050505; --text-main: #e0e6ed; --text-dim: #8892b0; --modal-bg: #111; }
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { background-color: var(--bg-color); color: var(--text-main); font-family: 'JetBrains Mono', monospace; min-height: 100vh; display: flex; flex-direction: column; align-items: center; overflow-x: hidden; position: relative; user-select: none; }
        #bgCanvas { position: fixed; top: 0; left: 0; width: 100%; height: 100%; z-index: -1; }
        .header { margin-top: 3rem; margin-bottom: 2rem; text-align: center; position: relative; z-index: 2; }
        .glitch-title { font-family: 'Share Tech Mono', monospace; font-size: 4rem; font-weight: bold; text-transform: uppercase; color: #fff; position: relative; letter-spacing: 4px; text-shadow: 2px 2px 0px var(--cyan); animation: glitch-skew 3s infinite linear alternate-reverse; }
        .glitch-title::before, .glitch-title::after { content: attr(data-text); position: absolute; top: 0; left: 0; width: 100%; height: 100%; }
        .glitch-title::before { left: 2px; text-shadow: -1px 0 var(--purple); clip: rect(44px, 450px, 56px, 0); animation: glitch-anim 5s infinite linear alternate-reverse; }
        .glitch-title::after { left: -2px; text-shadow: -1px 0 var(--cyan); clip: rect(44px, 450px, 56px, 0); animation: glitch-anim2 5s infinite linear alternate-reverse; }
        @keyframes glitch-anim { 0% { clip: rect(31px, 9999px, 91px, 0); } 20% { clip: rect(6px, 9999px, 86px, 0); } 40% { clip: rect(68px, 9999px, 11px, 0); } 100% { clip: rect(82px, 9999px, 2px, 0); } }
        @keyframes glitch-anim2 { 0% { clip: rect(81px, 9999px, 9px, 0); } 20% { clip: rect(7px, 9999px, 88px, 0); } 40% { clip: rect(18px, 9999px, 31px, 0); } 100% { clip: rect(32px, 9999px, 52px, 0); } }
        @keyframes glitch-skew { 0% { transform: skew(0deg); } 10% { transform: skew(-1deg); } 20% { transform: skew(1deg); } 100% { transform: skew(0deg); } }
        .region-selector { margin-bottom: 2rem; position: relative; z-index: 20; width: 450px; display: flex; flex-direction: column; gap: 10px; }
        .custom-select { position: relative; font-family: 'JetBrains Mono', monospace; font-size: 1.1rem; }
        .select-selected { background: rgba(255, 255, 255, 0.05); border: 1px solid rgba(255, 255, 255, 0.1); color: #fff; padding: 15px 20px; cursor: pointer; display: flex; align-items: center; justify-content: center; transition: 0.3s; border-radius: 12px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; position: relative; }
        .select-selected:hover { background: rgba(0, 243, 255, 0.1); border-color: rgba(0, 243, 255, 0.3); }
        .select-selected::after { content: ""; border: 6px solid transparent; border-color: #fff transparent transparent transparent; opacity: 0.7; position: absolute; right: 20px; top: 50%; transform: translateY(-25%); }
        .select-selected.select-arrow-active::after { border-color: transparent transparent #fff transparent; transform: translateY(-75%); }
        .select-items { position: absolute; background-color: #111; border: 1px solid rgba(255,255,255,0.1); top: 100%; left: 0; right: 0; z-index: 99; margin-top: 8px; border-radius: 12px; overflow: hidden; box-shadow: 0 10px 30px rgba(0,0,0,0.5); }
        .select-hide { display: none; }
        .select-item { padding: 18px 25px; cursor: pointer; border-bottom: 1px solid rgba(255,255,255,0.05); display: flex; align-items: center; justify-content: center; color: #ccc; transition: all 0.3s ease; white-space: nowrap; border-left: 4px solid transparent; overflow: hidden; text-overflow: ellipsis; }
        .select-item:last-child { border-bottom: none; }
        .select-item:hover { background: rgba(255,255,255,0.1); color: #fff; }
        .flag-icon { width: 24px; height: 18px; margin-right: 15px; vertical-align: middle; border-radius: 4px; box-shadow: 0 0 5px rgba(0,0,0,0.5); flex-shrink: 0; }
        .main-container { width: 95%; max-width: 1600px; display: grid; grid-template-columns: 1fr 1fr; gap: 25px; margin-bottom: 30px; position: relative; z-index: 5; }
        @media (max-width: 900px) { .main-container { grid-template-columns: 1fr; } }
        .glass-card { border-radius: 20px; padding: 25px; position: relative; display: flex; flex-direction: column; min-width: 0; width: 100%; border: 1px solid rgba(255,255,255,0.05); box-shadow: 0 10px 30px rgba(0,0,0,0.3); transition: transform 0.3s ease; }
        .glass-card:hover { transform: translateY(-3px); }
        .glass-card.card-v4 { background: rgba(0, 243, 255, 0.06); }
        .glass-card.card-v4 .card-title { color: var(--cyan); border-bottom: 1px solid rgba(0,243,255,0.2); }
        .glass-card.card-v6 { background: rgba(188, 19, 254, 0.06); }
        .glass-card.card-v6 .card-title { color: var(--purple); border-bottom: 1px solid rgba(188,19,254,0.2); }
        .glass-card.card-v6 .ip-action-box { color: var(--purple); background: rgba(188,19,254,0.1); border-color: rgba(188,19,254,0.2); }
        .glass-card.card-v6 .ip-action-box:hover { background: rgba(188,19,254,0.2); }
        .card-title { font-size: 1.2rem; margin-bottom: 20px; font-weight: bold; padding-bottom: 10px; letter-spacing: 1px; text-transform: uppercase; display: flex; justify-content: space-between; align-items: center; }
        .btn-file-test { font-family: 'JetBrains Mono', monospace; font-size: 0.9rem; padding: 8px 18px; border-radius: 8px; border: none; cursor: pointer; text-transform: uppercase; font-weight: 800; transition: all 0.2s; color: #000; box-shadow: 0 0 10px rgba(0,0,0,0.5); line-height: 1; }
        .btn-file-test:hover { transform: scale(1.05); filter: brightness(1.2); }
        .btn-file-test:disabled { background: #333 !important; color: #666 !important; cursor: not-allowed; box-shadow: none; }
        .card-v4 .btn-file-test { background: var(--cyan); box-shadow: 0 0 15px rgba(0, 243, 255, 0.3); }
        .card-v6 .btn-file-test { background: var(--purple); box-shadow: 0 0 15px rgba(188, 19, 254, 0.3); }
        .ip-action-box { background: rgba(0, 243, 255, 0.1); border: 1px solid rgba(0, 243, 255, 0.2); padding: 15px; text-align: center; font-size: 1.1rem; color: var(--cyan); cursor: pointer; border-radius: 12px; transition: all 0.2s ease; margin-bottom: 20px; font-weight: bold; }
        .ip-action-box:hover { background: rgba(0, 243, 255, 0.2); transform: scale(1.02); }
        .ip-action-box::after { content: 'CLICK TO TEST'; display: block; font-size: 0.6rem; color: rgba(255,255,255,0.6); margin-top: 6px; letter-spacing: 2px; }
        .terminal-output { background: rgba(0,0,0,0.4); border: 1px solid rgba(255,255,255,0.05); color: #ddd; padding: 15px; font-size: 0.8rem; height: 380px; overflow-y: auto; font-family: 'Consolas', 'Monaco', monospace; margin-bottom: 15px; border-radius: 12px; white-space: pre-wrap; word-break: break-all; width: 100%; }
        @media (max-width: 600px) { .terminal-output { height: 250px; } }
        .unlock-header { font-size: 0.75rem; color: #666; margin-bottom: 8px; text-transform: uppercase; letter-spacing: 1px; text-align: center; font-weight: bold; }
        .card-v4 .unlock-header { color: rgba(0,243,255,0.7); }
        .card-v6 .unlock-header { color: rgba(188,19,254,0.7); }
        .unlock-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; font-size: 0.8rem; margin-top: auto; border-top: 1px solid rgba(255,255,255,0.05); padding-top: 15px; }
        .unlock-item { display: flex; justify-content: space-between; align-items: center; background: rgba(0,0,0,0.2); padding: 10px 15px; border-radius: 8px; border: none; }
        .info-key { color: #fff; font-weight: 800; font-size: 0.85rem; letter-spacing: 0.5px; }
        .card-v4 .status-yes { color: var(--green); opacity: 1; font-weight: bold; }
        .card-v6 .status-yes { color: var(--pink); opacity: 1; font-weight: bold; }
        .status-no { color: #555; font-size: 0.75rem; font-weight: bold; }
        .modal-overlay { position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.8); z-index: 100; display: none; justify-content: center; align-items: center; backdrop-filter: blur(8px); }
        .modal { background: var(--modal-bg); border: 1px solid rgba(255,255,255,0.1); box-shadow: 0 20px 50px rgba(0,0,0,0.8); padding: 40px; border-radius: 24px; width: 550px; position: relative; max-width: 95%; text-align: center; animation: modalFadeIn 0.2s ease-out; }
        @keyframes modalFadeIn { from { opacity: 0; transform: scale(0.95); } to { opacity: 1; transform: scale(1); } }
        .modal h3 { color: #fff; margin-bottom: 25px; font-family: 'Share Tech Mono'; font-size: 1.8rem; letter-spacing: 2px; }
        .action-btn-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; }
        .action-btn { background: rgba(255,255,255,0.05); border: none; color: #fff; padding: 18px 0; cursor: pointer; font-family: 'JetBrains Mono'; font-weight: bold; transition: 0.2s; text-transform: uppercase; letter-spacing: 1px; border-radius: 12px; }
        .action-btn:hover { background: var(--cyan); color: #000; }
        .modal-input { width: 100%; padding: 18px; margin-bottom: 25px; background: rgba(255,255,255,0.05); border: 1px solid transparent; color: #fff; font-family: 'JetBrains Mono'; outline: none; text-align: center; font-size: 1.2rem; transition: 0.3s; border-radius: 12px; }
        .modal-input:focus { background: rgba(255,255,255,0.1); border-color: var(--cyan); }
        .btn-confirm { background: var(--cyan); color: #000; width: 100%; padding: 18px; border: none; font-weight: bold; cursor: pointer; font-size: 1.1rem; text-transform: uppercase; letter-spacing: 1px; transition: 0.3s; border-radius: 12px; }
        .btn-confirm:hover { background: #fff; transform: translateY(-2px); box-shadow: 0 5px 15px rgba(255,255,255,0.3); }
        .btn-close { background: transparent; border: none; color: #666; margin-top: 20px; cursor: pointer; text-decoration: underline; letter-spacing: 1px; }
        .msg-content { color: #ccc; margin-bottom: 30px; font-size: 1rem; line-height: 1.6; }
        footer { margin-top: auto; padding: 20px; font-size: 0.8rem; color: rgba(255,255,255,0.2); z-index: 5; }
        #cf-widget-container { margin: 20px auto; min-height: 65px; display: flex; justify-content: center; }
    </style>
</head>
<body>

    <canvas id="bgCanvas"></canvas>

    <div class="header">
        <div class="glitch-title" data-text="$SITE_TITLE">$SITE_TITLE</div>
        <div style="font-size: 0.9rem; color: var(--cyan); margin-top: 10px; letter-spacing: 3px; opacity: 0.7;">NETWORK DIAGNOSTIC TOOL</div>
    </div>

    <div class="region-selector">
        <div class="custom-select" id="customNodeSelect">
            <div class="select-selected" id="currentSelectDisplay" onclick="toggleSelect()">
                <span style="color:#888;">Select Node...</span>
            </div>
            <div class="select-items select-hide" id="customOptions"></div>
        </div>
    </div>

    <div class="main-container">
        <!-- IPv4 Card -->
        <div class="glass-card card-v4">
            <div class="card-title">
                <span>🌐 IPv4 Network</span>
                <button class="btn-file-test" id="btn-test-v4" onclick="initFileTest('IPv4')" disabled>1G File Test</button>
            </div>
            <div class="ip-action-box" onclick="openActionModal('IPv4')"><span id="ipv4-addr">--</span></div>
            <div class="terminal-output" id="term-v4">[Waiting for Node Selection...]</div>
            
            <div class="unlock-header">Streaming Services & AI Unlock Monitor (30m Auto-update)</div>
            <div class="unlock-grid" id="unlock-list-v4"></div>
        </div>

        <!-- IPv6 Card -->
        <div class="glass-card card-v6">
            <div class="card-title">
                <span>🪐 IPv6 Network</span>
                <button class="btn-file-test" id="btn-test-v6" onclick="initFileTest('IPv6')" disabled>1G File Test</button>
            </div>
            <div class="ip-action-box" onclick="openActionModal('IPv6')"><span id="ipv6-addr">--</span></div>
            <div class="terminal-output" id="term-v6">[Waiting for Node Selection...]</div>
            
            <div class="unlock-header">Streaming Services & AI Unlock Monitor (30m Auto-update)</div>
            <div class="unlock-grid" id="unlock-list-v6"></div>
        </div>
    </div>

    <footer>&copy; 2023-2025 BitsFlowCloud Network. All Rights Reserved.</footer>

    <!-- Modals -->
    <div class="modal-overlay" id="modal-action">
        <div class="modal">
            <h3>SELECT ACTION</h3>
            <p style="margin-bottom: 20px; color: #aaa;">Protocol: <span id="modal-proto-label" style="color:var(--cyan)">--</span></p>
            <div class="action-btn-grid">
                <button class="action-btn" onclick="selectTool('ping')">PING</button>
                <button class="action-btn" onclick="selectTool('mtr')">MTR</button>
                <button class="action-btn" onclick="selectTool('route')">ROUTE</button>
                <button class="action-btn" onclick="selectTool('iperf3')">IPERF3</button>
            </div>
            <button class="btn-close" onclick="closeAllModals()">Cancel</button>
        </div>
    </div>
    
    <div class="modal-overlay" id="modal-target">
        <div class="modal">
            <h3 id="target-title">ENTER TARGET</h3>
            <input type="text" id="target-input" class="modal-input" placeholder="" maxlength="60">
            <button class="btn-confirm" onclick="runSimulation()">START TEST</button>
            <button class="btn-close" onclick="closeAllModals()">Cancel</button>
        </div>
    </div>

    <div class="modal-overlay" id="modal-message">
        <div class="modal">
            <h3 id="msg-title">NOTICE</h3>
            <div id="msg-body" class="msg-content">Message goes here.</div>
            <button class="btn-confirm" onclick="closeMsgModal()">OK</button>
        </div>
    </div>
    <div class="modal-overlay" id="modal-cf">
        <div class="modal" style="width: 400px; padding: 20px;">
            <h3>SECURITY CHECK</h3>
            <div id="cf-widget-container"></div>
            <div id="cf-status" style="color:#888; font-size:0.8rem; margin-top:10px;">Please complete the check to download.</div>
            <button class="btn-close" onclick="closeAllModals()">Cancel</button>
        </div>
    </div>

    <script>
        // Inject Cloudflare Site Key here
        const CF_SITE_KEY = '$CF_SITE_KEY';
        
        const canvas = document.getElementById('bgCanvas'); const ctx = canvas.getContext('2d');
        let width, height; let particles = [];
        function initCanvas() { width = canvas.width = window.innerWidth; height = canvas.height = window.innerHeight; particles = []; for(let i=0; i<100; i++) particles.push({ x: Math.random()*width, y: Math.random()*height, z: Math.random()*2+0.5, size: Math.random()*2 }); }
        function drawCanvas() { ctx.fillStyle = '#050505'; ctx.fillRect(0, 0, width, height); ctx.fillStyle = '#00f3ff'; particles.forEach(p => { p.y += p.z * 0.5; if(p.y > height) { p.y = 0; p.x = Math.random() * width; } ctx.globalAlpha = (p.z - 0.5) / 2 * 0.5; ctx.beginPath(); ctx.arc(p.x, p.y, p.size, 0, Math.PI*2); ctx.fill(); }); ctx.globalAlpha = 1; requestAnimationFrame(drawCanvas); }
        window.addEventListener('resize', initCanvas); initCanvas(); drawCanvas();

        let nodeData = {}; let currentProto = ''; let currentTool = ''; let currentNode = null; let limitInterval = null; let turnstileWidgetId = null; let pendingDownloadProto = null;
        const safeStorage = { getItem: (key) => { try { return localStorage.getItem(key); } catch(e) { return null; } }, setItem: (key, val) => { try { localStorage.setItem(key, val); } catch(e) {} } };
        
        function escapeHtml(text) { 
            if (!text) return text; 
            return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#039;"); 
        }

        async function initCustomDropdown() {
            const optionsContainer = document.getElementById('customOptions'); 
            optionsContainer.innerHTML = '<div class="select-item" style="color:#888;">Loading nodes...</div>';
            try {
                const response = await fetch('api.php', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: 'action=get_nodes' });
                const json = await response.json();
                if (json.status !== 'success') throw new Error(json.message || 'Failed to load nodes');
                
                nodeData = json.data;
                optionsContainer.innerHTML = '';
                const keys = Object.keys(nodeData);
                
                if (keys.length === 0) { document.getElementById("currentSelectDisplay").innerHTML = '<span style="color:#666;">No Nodes Configured</span>'; return; }
                
                keys.forEach(key => {
                    const node = nodeData[key]; 
                    const flagCode = node.country || node.flag || 'xx';
                    const div = document.createElement('div'); div.className = 'select-item'; 
                    div.innerHTML = \`<span style="display:flex; align-items:center; overflow:hidden; text-overflow:ellipsis;"><img src="https://flagcdn.com/24x18/\${escapeHtml(flagCode.toLowerCase())}.png" class="flag-icon"> \${escapeHtml(node.name)}</span>\`;
                    div.onclick = function() { updateSelected(key, node.name, flagCode); }; 
                    optionsContainer.appendChild(div);
                });
                if(keys.length > 0) { const firstKey = keys[0]; const n = nodeData[firstKey]; updateSelected(firstKey, n.name, n.country || n.flag, false); }
            } catch (e) {
                console.error(e); optionsContainer.innerHTML = \`<div class="select-item" style="color:var(--pink);">\${escapeHtml(e.message)}</div>\`;
            }
        }

        function toggleSelect() { document.getElementById("customOptions").classList.toggle("select-hide"); document.getElementById("currentSelectDisplay").classList.toggle("select-arrow-active"); }
        function updateSelected(key, name, flag, close = true) {
            document.getElementById("currentSelectDisplay").innerHTML = \`<span style="display:flex; align-items:center; overflow:hidden; text-overflow:ellipsis;"><img src="https://flagcdn.com/24x18/\${escapeHtml(flag.toLowerCase())}.png" class="flag-icon"> \${escapeHtml(name)}</span>\`;
            currentNode = key; switchNode();
            if(close) { document.getElementById("customOptions").classList.add("select-hide"); document.getElementById("currentSelectDisplay").classList.remove("select-arrow-active"); }
        }
        window.onclick = function(e) { if (!e.target.matches('.select-selected') && !e.target.matches('.select-selected *')) { const myDropdown = document.getElementById("customOptions"); if (!myDropdown.classList.contains('select-hide')) { myDropdown.classList.add('select-hide'); document.getElementById("currentSelectDisplay").classList.remove("select-arrow-active"); } } }

        function switchNode() {
            if (!currentNode || !nodeData[currentNode]) return;
            const data = nodeData[currentNode];
            document.getElementById('ipv4-addr').innerText = data.ipv4 || data.ip4 || '--'; 
            document.getElementById('ipv6-addr').innerText = data.ipv6 || data.ip6 || '--';
            document.getElementById('term-v4').innerHTML = \`<div style="margin-bottom:10px; color:#888;">[System] Connected to \${escapeHtml(data.name)}</div>\`;
            document.getElementById('term-v6').innerHTML = \`<div style="margin-bottom:10px; color:#888;">[System] Connected to \${escapeHtml(data.name)}</div>\`;
            
            let v4Data = null;
            let v6Data = null;
            if (data.unlock) {
                if (data.unlock.v4 || data.unlock.v6) {
                    v4Data = data.unlock.v4;
                    v6Data = data.unlock.v6;
                } else {
                    v4Data = data.unlock; 
                    v6Data = null;
                }
            }
            renderUnlockList('v4', v4Data); 
            renderUnlockList('v6', v6Data);
            
            resetTestButtons(); 
        }

        function renderUnlockList(ver, unlockData) {
            const listId = \`unlock-list-\${ver}\`; const container = document.getElementById(listId); 
            let html = ''; 
            const services = ['Netflix', 'YouTube', 'Disney+', 'TikTok', 'Spotify', 'Gemini'];
            services.forEach(s => { 
                const key = s.toLowerCase().replace('+','');
                let resultText = unlockData && unlockData[key] ? unlockData[key] : "No";
                let isUnlocked = false; 
                let displayText = "NO";
                let statusClass = "status-no";

                if (resultText.toLowerCase().includes("yes")) {
                    isUnlocked = true;
                    statusClass = "status-yes";
                    displayText = "YES";
                    const regionMatch = resultText.match(/Region:\s*([A-Za-z]{2})/i);
                    if (regionMatch) {
                        displayText += \` [\${regionMatch[1].toUpperCase()}]\`;
                    }
                }
                html += \`<div class="unlock-item"><span class="info-key">\${s}</span><span class="\${statusClass}">\${displayText}</span></div>\`; 
            });
            container.innerHTML = html;
        }
        
        function showCustomAlert(msg, title = "NOTICE") { document.getElementById('msg-title').innerText = title; document.getElementById('msg-body').innerHTML = msg; document.getElementById('modal-message').style.display = 'flex'; }
        function closeMsgModal() { if(limitInterval) { clearInterval(limitInterval); limitInterval = null; } document.getElementById('modal-message').style.display = 'none'; }
        function openActionModal(proto) { if (!currentNode) return; currentProto = proto; document.getElementById('modal-proto-label').innerText = proto; document.getElementById('modal-action').style.display = 'flex'; }
        
        function selectTool(tool) { 
            currentTool = tool; 
            document.getElementById('modal-action').style.display = 'none'; 
            if (tool === 'iperf3') { 
                showIperfCommand(); 
            } else { 
                document.getElementById('target-title').innerText = \`ENTER TARGET \${currentProto} ADDRESS\`; 
                document.getElementById('target-input').value = ''; 
                document.getElementById('target-input').placeholder = currentProto === 'IPv4' ? 'e.g. 1.1.1.1' : 'e.g. 2606:4700::1111'; 
                document.getElementById('modal-target').style.display = 'flex'; 
                document.getElementById('target-input').focus(); 
            } 
        }
        
        function closeAllModals() { if(limitInterval) { clearInterval(limitInterval); limitInterval = null; } document.getElementById('modal-action').style.display = 'none'; document.getElementById('modal-target').style.display = 'none'; document.getElementById('modal-cf').style.display = 'none'; }
        function startCountdown(seconds, elementId) { if(limitInterval) clearInterval(limitInterval); let remaining = seconds; const el = document.getElementById(elementId); if(el) el.innerText = remaining; limitInterval = setInterval(() => { remaining--; if(el) el.innerText = remaining; if(remaining <= 0) { clearInterval(limitInterval); closeMsgModal(); } }, 1000); }

        async function showIperfCommand() {
            if (!currentNode) return;
            const limitKey = \`iperf_limit_\${currentNode}_\${currentProto}_\${new Date().getHours()}\`;
            let count = parseInt(safeStorage.getItem(limitKey) || "0");
            if (count >= 5) { 
                 showCustomAlert(\`<span style="color:var(--pink)">Hourly Limit Reached!</span>\`, "ACCESS DENIED"); 
                 return; 
            }
            showCustomAlert("Requesting server resource...", "PLEASE WAIT");
            try {
                const formData = new FormData();
                formData.append('action', 'run_tool');
                formData.append('node_id', currentNode);
                formData.append('tool', 'iperf3');
                formData.append('target', '0.0.0.0');
                formData.append('proto', currentProto);

                const response = await fetch('api.php', { method: 'POST', body: formData });
                const text = await response.text();

                if (text.includes("iperf3 -c")) {
                    const command = text.trim();
                    count++; safeStorage.setItem(limitKey, count);
                    const modalContent = \`<div style="text-align:left; background:#222; padding:15px; border-radius:8px; font-family:monospace; margin-bottom:15px; border:1px solid #444; color:#00ff9d; word-break:break-all; cursor:pointer;" onclick="copyToClipboard('\${command}')">\${command}<div style="font-size:0.7rem; color:#888; margin-top:5px; text-align:right;">(Click to Copy)</div></div><div style="color:#f1c40f; font-size:0.9rem; font-weight:bold; margin-bottom:5px;">⚠️ Port valid for 60 seconds.</div>\`;
                    showCustomAlert(modalContent, \`IPERF3 SESSION (\${currentProto})\`);
                } else {
                    try {
                        const json = JSON.parse(text);
                        showCustomAlert("Server Error: " + (json.message || "Unknown"), "ERROR");
                    } catch(e) {
                         showCustomAlert("Server Error: " + escapeHtml(text), "ERROR");
                    }
                }
            } catch (e) {
                showCustomAlert("Network Error: " + escapeHtml(e.message), "ERROR");
            }
        }

        function copyToClipboard(text) { if (navigator.clipboard && window.isSecureContext) { navigator.clipboard.writeText(text).then(() => showCustomAlert("Copied!", "SUCCESS")).catch(() => fallbackCopy(text)); } else { fallbackCopy(text); } }
        function fallbackCopy(text) { var t = document.createElement("textarea"); t.value = text; t.style.position="fixed"; document.body.appendChild(t); t.focus(); t.select(); try { document.execCommand('copy'); showCustomAlert("Copied!", "SUCCESS"); } catch(e){ showCustomAlert("Failed to copy", "ERROR"); } document.body.removeChild(t); }

        async function runSimulation() {
            const rawTarget = document.getElementById('target-input').value.trim();
            if(!rawTarget) { showCustomAlert("Please enter a target IP!", "INPUT ERROR"); return; }
            
            if (!/^[a-zA-Z0-9.:-]+$/.test(rawTarget)) { 
                showCustomAlert("Invalid characters detected.<br>Only letters, numbers, dots, colons and hyphens allowed.", "SECURITY ALERT"); 
                return; 
            }
            
            const safeTarget = escapeHtml(rawTarget);
            closeAllModals(); 
            const termId = currentProto === 'IPv4' ? 'term-v4' : 'term-v6'; const term = document.getElementById(termId);
            term.innerHTML = \`<div style="margin-bottom:10px; color:#888;">[System] Connected to \${escapeHtml(nodeData[currentNode].name)}</div>\`;
            term.innerHTML += \`<span style="color:var(--cyan)">root@\${escapeHtml(nodeData[currentNode].country || 'xx')}:~#</span> \${escapeHtml(currentTool)} \${safeTarget}\\n\`; 
            term.innerHTML += \`> Initiating \${escapeHtml(currentTool)}...\\n\\n\`; term.scrollTop = term.scrollHeight;
            try {
                const formData = new FormData(); formData.append('action', 'run_tool'); formData.append('node_id', currentNode); formData.append('tool', currentTool); formData.append('target', rawTarget); formData.append('proto', currentProto);
                const response = await fetch('api.php', { method: 'POST', body: formData });
                const text = await response.text();
                
                if (text.startsWith('{') && text.includes('"status":"error"')) {
                    const json = JSON.parse(text);
                     term.innerHTML += \`<span style="color:var(--pink)">Error: \${escapeHtml(json.message)}</span>\\n\`;
                } else {
                     term.innerHTML += \`<span style="color:#eee">\${escapeHtml(text)}</span>\\n\`; 
                     term.innerHTML += \`\\n> Done.\\n\`;
                }
            } catch (e) { term.innerHTML += \`<span style="color:var(--pink)">System Error: \${escapeHtml(e.message)}</span>\\n\`; }
            term.scrollTop = term.scrollHeight;
        }
        function resetTestButtons() { const hasNode = !!currentNode; document.getElementById('btn-test-v4').disabled = !hasNode; document.getElementById('btn-test-v6').disabled = !hasNode; }

        function initFileTest(proto) {
            if (!currentNode) return;
            pendingDownloadProto = proto;
            document.getElementById('modal-cf').style.display = 'flex';
            document.getElementById('cf-status').innerText = "Please complete the check...";
            document.getElementById('cf-status').style.color = "#888";
            if (turnstileWidgetId === null) {
                turnstileWidgetId = turnstile.render('#cf-widget-container', {
                    sitekey: CF_SITE_KEY, 
                    theme: 'light',
                    callback: function(token) { onTurnstileSuccess(token); },
                    'expired-callback': function() { document.getElementById('cf-status').innerText = "Check expired. Please click again."; }
                });
            } else { turnstile.reset(turnstileWidgetId); }
        }

        function onTurnstileSuccess(token) {
            const targetNode = currentNode;
            const proto = pendingDownloadProto;
            const node = nodeData[targetNode];

            document.getElementById('cf-status').innerText = "Success! Starting download...";
            document.getElementById('cf-status').style.color = "#00ff9d";

            setTimeout(() => {
                closeAllModals();
                let downloadUrl = '';
                
                if (proto === 'IPv4') {
                    if (node.ipv4) downloadUrl = \`http://\${node.ipv4}/1gb.bin\`;
                } else {
                    if (node.ipv6) {
                        let v6 = node.ipv6;
                        if (v6.indexOf(':') > -1 && v6.indexOf('[') === -1) v6 = \`[\${v6}]\`;
                        downloadUrl = \`http://\${v6}/1gb.bin\`;
                    }
                }
                
                if(downloadUrl) {
                    window.open(downloadUrl, '_blank', 'noopener,noreferrer');
                } else {
                    showCustomAlert("IP address not configured for this protocol.", "ERROR");
                }
            }, 500);
        }

        window.onload = function() { initCustomDropdown(); };
    </script>
</body>
</html>
EOF

    # --- 生成 api.php ---
    cat << 'EOF' > "$WEB_ROOT/api.php"
<?php
error_reporting(0);
header('Content-Type: application/json; charset=utf-8');
$config = require 'config.php';
$action = $_POST['action'] ?? '';

if ($action === 'get_nodes') {
    $nodes = $config['nodes'];
    $final_nodes = [];
    foreach ($nodes as $id => $node) {
        $unlock_data = ['v4' => null, 'v6' => null];
        $postData = ['key' => $node['key'], 'action' => 'get_unlock'];
        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, $node['api_url']);
        curl_setopt($ch, CURLOPT_POST, 1);
        curl_setopt($ch, CURLOPT_POSTFIELDS, http_build_query($postData));
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, 2); 
        curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 2);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false);
        $response = curl_exec($ch);
        $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        if ($http_code == 200 && $response) {
            $json = json_decode($response, true);
            if (is_array($json)) { $unlock_data = $json; }
        }
        $node['unlock'] = $unlock_data;
        unset($node['key']); unset($node['api_url']);
        $final_nodes[$id] = $node;
    }
    echo json_encode(['status' => 'success', 'data' => $final_nodes]);
    exit;
}

if ($action === 'run_tool') {
    $node_id = $_POST['node_id'] ?? '';
    if (!isset($config['nodes'][$node_id])) { echo json_encode(['status' => 'error', 'message' => 'Node not found']); exit; }
    $node = $config['nodes'][$node_id];
    $postData = $_POST; $postData['key'] = $node['key'];
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $node['api_url']);
    curl_setopt($ch, CURLOPT_POST, 1);
    curl_setopt($ch, CURLOPT_POSTFIELDS, http_build_query($postData));
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 45); 
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
    curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false);
    $response = curl_exec($ch);
    $err = curl_error($ch);
    $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    if ($err) { echo "Error connecting to node: $err"; } elseif ($http_code == 403) { echo "Error: Authorization Failed (Check API Key)"; } else { echo $response; }
    exit;
}
echo json_encode(['status' => 'error', 'message' => 'Invalid action']);
EOF

    # 修复权限
    chmod -R 755 "$WEB_ROOT"
    
    echo -e "${GREEN}主控端文件安装/更新完成！${NC}"
}

# ==========================================
# 3. 添加节点
# ==========================================
function add_node() {
    if [ ! -f "$SETTINGS_FILE" ]; then configure_install; fi
    source "$SETTINGS_FILE"
    CONFIG_FILE="$WEB_ROOT/config.php"

    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}错误: config.php 不存在，请先运行安装选项。${NC}"
        return
    fi
    
    echo -e "${YELLOW}--- 添加新节点 ---${NC}"
    read -p "请输入节点 ID (例如 de01): " NODE_ID
    read -p "请输入节点名称 (例如 DE - Frankfurt): " NODE_NAME
    read -p "请输入国家代码 (例如 de): " NODE_COUNTRY
    read -p "请输入 IPv4 地址: " NODE_IPV4
    read -p "请输入 IPv6 地址 (留空则不显示): " NODE_IPV6
    read -p "请输入 Agent API 地址 (例如 http://1.2.3.4/agent.php): " NODE_API
    read -p "请输入节点通信密钥: " NODE_KEY

    NEW_NODE_PHP="        '$NODE_ID' => [
            'name'    => '$NODE_NAME',
            'country' => '$NODE_COUNTRY',
            'ipv4'    => '$NODE_IPV4',
            'ipv6'    => '$NODE_IPV6',
            'api_url' => '$NODE_API',
            'key'     => '$NODE_KEY',
        ],
        //_NEXT_NODE_"

    # 安全插入
    TEMP_FILE=$(mktemp)
    awk -v new_node="$NEW_NODE_PHP" '{sub(/\/\/_NEXT_NODE_/, new_node); print}' "$CONFIG_FILE" > "$TEMP_FILE" && mv "$TEMP_FILE" "$CONFIG_FILE"
    
    chmod 644 "$CONFIG_FILE"
    echo -e "${GREEN}节点 $NODE_NAME 已成功添加到 config.php!${NC}"
}

# ==========================================
# 4. 服务管理 (启动/停止)
# ==========================================
function manage_service() {
    if [ ! -f "$SETTINGS_FILE" ]; then configure_install; fi
    source "$SETTINGS_FILE"
    
    echo ""
    echo "--- 主控端服务管理 ---"
    echo "1. 启动 PHP 后端服务 (Start)"
    echo "2. 停止 PHP 后端服务 (Stop)"
    echo "3. 重启 PHP 后端服务 (Restart)"
    echo "4. 查看状态 (Status)"
    echo "5. 配置 SSL (HTTPS) - 推荐"
    echo "6. 返回主菜单"
    read -p "请选择: " svc_choice

    case $svc_choice in
        1)
            if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
                echo -e "${YELLOW}PHP 服务已在运行 (PID: $(cat $PID_FILE))${NC}"
            else
                if netstat -tuln | grep ":$SERVER_PORT " > /dev/null; then
                     echo -e "${RED}端口 $SERVER_PORT 已被占用！无法启动。${NC}"
                     return
                fi
                # 启动 PHP 内置服务器
                nohup php -S 127.0.0.1:$SERVER_PORT -t "$WEB_ROOT" > "$LOG_FILE" 2>&1 &
                echo $! > "$PID_FILE"
                echo -e "${GREEN}PHP 后端已启动! (监听 127.0.0.1:$SERVER_PORT)${NC}"
            fi
            ;;
        2)
            if [ -f "$PID_FILE" ]; then
                kill $(cat "$PID_FILE") 2>/dev/null
                rm "$PID_FILE"
                echo -e "${GREEN}PHP 服务已停止。${NC}"
            else
                echo -e "${RED}服务未运行。${NC}"
            fi
            ;;
        3)
            if [ -f "$PID_FILE" ]; then kill $(cat "$PID_FILE") 2>/dev/null; rm "$PID_FILE"; fi
            nohup php -S 127.0.0.1:$SERVER_PORT -t "$WEB_ROOT" > "$LOG_FILE" 2>&1 &
            echo $! > "$PID_FILE"
            echo -e "${GREEN}PHP 服务已重启!${NC}"
            ;;
        4)
            if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
                echo -e "${GREEN}PHP 状态: 运行中 (PID: $(cat $PID_FILE))${NC}"
            else
                echo -e "${RED}PHP 状态: 未运行${NC}"
            fi
            ;;
        5)
            configure_ssl
            ;;
        *) return ;;
    esac
}

# ==========================================
# 5. SSL 配置 (Nginx + Certbot)
# ==========================================
function configure_ssl() {
    if [ ! -f "$SETTINGS_FILE" ]; then configure_install; fi
    source "$SETTINGS_FILE"

    echo -e "${YELLOW}>>> 开始配置 SSL (使用 Let's Encrypt)${NC}"
    echo -e "${YELLOW}注意: 此操作将安装 Nginx 并占用 80/443 端口。${NC}"
    echo -e "${YELLOW}请确保您的域名 ($SITE_TITLE 对应的域名) 已解析到本机 IP！${NC}"
    
    read -p "请输入您的域名 (例如 lg.example.com): " SSL_DOMAIN
    read -p "请输入您的邮箱 (用于证书通知): " SSL_EMAIL
    
    if [ -z "$SSL_DOMAIN" ] || [ -z "$SSL_EMAIL" ]; then
        echo -e "${RED}域名或邮箱不能为空！${NC}"
        return
    fi

    echo -e "${YELLOW}正在安装 Nginx 和 Certbot...${NC}"
    if [ -f /etc/debian_version ]; then
        apt-get update
        apt-get install -y nginx python3-certbot-nginx
    elif [ -f /etc/redhat-release ]; then
        yum install -y nginx python3-certbot-nginx
    fi

    # 确保 PHP 后端在运行
    if [ ! -f "$PID_FILE" ] || ! kill -0 $(cat "$PID_FILE") 2>/dev/null; then
        echo -e "${YELLOW}正在启动 PHP 后端...${NC}"
        nohup php -S 127.0.0.1:$SERVER_PORT -t "$WEB_ROOT" > "$LOG_FILE" 2>&1 &
        echo $! > "$PID_FILE"
    fi

    echo -e "${YELLOW}正在生成 Nginx 配置...${NC}"
    
    # 创建 Nginx 配置 (先只配 HTTP，让 Certbot 自动改 HTTPS)
    cat << EOF > /etc/nginx/conf.d/lg_master.conf
server {
    listen 80;
    server_name $SSL_DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:$SERVER_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

    # 重载 Nginx
    systemctl enable nginx
    systemctl restart nginx

    echo -e "${YELLOW}正在申请证书...${NC}"
    certbot --nginx --non-interactive --agree-tos -m "$SSL_EMAIL" -d "$SSL_DOMAIN"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}SSL 证书申请成功！${NC}"
        echo -e "${GREEN}您的 Looking Glass 现在可以通过 https://$SSL_DOMAIN 访问。${NC}"
        
        # 添加自动续期任务
        (crontab -l 2>/dev/null | grep -v "certbot renew") | crontab -
        (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet") | crontab -
        echo -e "${GREEN}已添加每日自动续期任务。${NC}"
    else
        echo -e "${RED}证书申请失败。请检查域名解析是否正确，以及防火墙是否开放 80/443 端口。${NC}"
    fi
}

# ==========================================
# 主菜单
# ==========================================
check_env

while true; do
    echo ""
    echo "1. 配置安装参数 (目录/标题/端口)"
    echo "2. 安装/更新 核心文件"
    echo "3. 添加新节点 (Add Node)"
    echo "4. 服务管理 (启动/停止/状态)"
    echo "5. 配置 SSL (HTTPS)"
    echo "6. 退出"
    read -p "请选择 [1-6]: " choice
    case $choice in
        1) configure_install ;;
        2) install_files ;;
        3) add_node ;;
        4) manage_service ;;
        5) configure_ssl ;;
        6) exit 0 ;;
        *) echo -e "${RED}无效选项${NC}" ;;
    esac
done
