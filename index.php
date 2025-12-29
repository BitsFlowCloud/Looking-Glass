<?php 
// 1. 加载配置文件
$config = [];
if (file_exists('config.php')) {
    $config = require 'config.php';
}

// 2. 定义变量 (默认值使用你提供的原始HTML中的值)
$siteTitle = $config['site_title'] ?? 'BitsFlowCloud Looking Glass';
$siteHeader = $config['site_header'] ?? 'BitsFlowCloud Looking Glass';
$footerText = $config['footer_text'] ?? '&copy; 2023-2025 BitsFlowCloud Network. All Rights Reserved.';
$cfSiteKey = $config['cf_site_key'] ?? '0x4AAAAAACJhmoIhycq-YD13';

// 3. 安全输出函数
function e($str) {
    return htmlspecialchars($str ?? '', ENT_QUOTES, 'UTF-8');
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php echo e($siteTitle); ?></title>
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
        
        .select-selected { 
            background: rgba(255, 255, 255, 0.05); 
            border: 1px solid rgba(255, 255, 255, 0.1); 
            color: #fff; 
            padding: 15px 20px; 
            cursor: pointer; 
            display: flex; 
            align-items: center; 
            justify-content: center; 
            transition: 0.3s; 
            border-radius: 12px; 
            white-space: nowrap; 
            overflow: hidden; 
            text-overflow: ellipsis; 
            position: relative; 
        }
        .select-selected:hover { background: rgba(0, 243, 255, 0.1); border-color: rgba(0, 243, 255, 0.3); }
        
        .select-selected::after { 
            content: ""; 
            border: 6px solid transparent; 
            border-color: #fff transparent transparent transparent; 
            opacity: 0.7; 
            position: absolute;
            right: 20px;
            top: 50%;
            transform: translateY(-25%);
        }
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

        .unlock-header { 
            font-size: 0.75rem; 
            color: #666; 
            margin-bottom: 8px; 
            text-transform: uppercase; 
            letter-spacing: 1px; 
            text-align: center; 
            font-weight: bold; 
        }
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
        <div class="glitch-title" data-text="<?php echo e($siteHeader); ?>"><?php echo e($siteHeader); ?></div>
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
            
            <!-- 流媒体标题 -->
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
            
            <!-- 流媒体标题 -->
            <div class="unlock-header">Streaming Services & AI Unlock Monitor (30m Auto-update)</div>
            <div class="unlock-grid" id="unlock-list-v6"></div>
        </div>
    </div>

    <footer><?php echo $footerText; ?></footer>

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
                    div.innerHTML = `<span style="display:flex; align-items:center; overflow:hidden; text-overflow:ellipsis;"><img src="https://flagcdn.com/24x18/${escapeHtml(flagCode.toLowerCase())}.png" class="flag-icon"> ${escapeHtml(node.name)}</span>`;
                    div.onclick = function() { updateSelected(key, node.name, flagCode); }; 
                    optionsContainer.appendChild(div);
                });
                if(keys.length > 0) { const firstKey = keys[0]; const n = nodeData[firstKey]; updateSelected(firstKey, n.name, n.country || n.flag, false); }
            } catch (e) {
                console.error(e); optionsContainer.innerHTML = `<div class="select-item" style="color:var(--pink);">${escapeHtml(e.message)}</div>`;
            }
        }

        function toggleSelect() { document.getElementById("customOptions").classList.toggle("select-hide"); document.getElementById("currentSelectDisplay").classList.toggle("select-arrow-active"); }
        function updateSelected(key, name, flag, close = true) {
            document.getElementById("currentSelectDisplay").innerHTML = `<span style="display:flex; align-items:center; overflow:hidden; text-overflow:ellipsis;"><img src="https://flagcdn.com/24x18/${escapeHtml(flag.toLowerCase())}.png" class="flag-icon"> ${escapeHtml(name)}</span>`;
            currentNode = key; switchNode();
            if(close) { document.getElementById("customOptions").classList.add("select-hide"); document.getElementById("currentSelectDisplay").classList.remove("select-arrow-active"); }
        }
        window.onclick = function(e) { if (!e.target.matches('.select-selected') && !e.target.matches('.select-selected *')) { const myDropdown = document.getElementById("customOptions"); if (!myDropdown.classList.contains('select-hide')) { myDropdown.classList.add('select-hide'); document.getElementById("currentSelectDisplay").classList.remove("select-arrow-active"); } } }

        function switchNode() {
            if (!currentNode || !nodeData[currentNode]) return;
            const data = nodeData[currentNode];
            document.getElementById('ipv4-addr').innerText = data.ipv4 || data.ip4 || '--'; 
            document.getElementById('ipv6-addr').innerText = data.ipv6 || data.ip6 || '--';
            document.getElementById('term-v4').innerHTML = `<div style="margin-bottom:10px; color:#888;">[System] Connected to ${escapeHtml(data.name)}</div>`;
            document.getElementById('term-v6').innerHTML = `<div style="margin-bottom:10px; color:#888;">[System] Connected to ${escapeHtml(data.name)}</div>`;
            
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
            const listId = `unlock-list-${ver}`; const container = document.getElementById(listId); 
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
                        displayText += ` [${regionMatch[1].toUpperCase()}]`;
                    }
                }

                html += `<div class="unlock-item"><span class="info-key">${s}</span><span class="${statusClass}">${displayText}</span></div>`; 
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
                document.getElementById('target-title').innerText = `ENTER TARGET ${currentProto} ADDRESS`; 
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
            const limitKey = `iperf_limit_${currentNode}_${currentProto}_${new Date().getHours()}`;
            let count = parseInt(safeStorage.getItem(limitKey) || "0");
            if (count >= 5) { 
                 showCustomAlert(`<span style="color:var(--pink)">Hourly Limit Reached!</span>`, "ACCESS DENIED"); 
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
                    const modalContent = `<div style="text-align:left; background:#222; padding:15px; border-radius:8px; font-family:monospace; margin-bottom:15px; border:1px solid #444; color:#00ff9d; word-break:break-all; cursor:pointer;" onclick="copyToClipboard('${command}')">${command}<div style="font-size:0.7rem; color:#888; margin-top:5px; text-align:right;">(Click to Copy)</div></div><div style="color:#f1c40f; font-size:0.9rem; font-weight:bold; margin-bottom:5px;">⚠️ Port valid for 60 seconds.</div>`;
                    showCustomAlert(modalContent, `IPERF3 SESSION (${currentProto})`);
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
            term.innerHTML = `<div style="margin-bottom:10px; color:#888;">[System] Connected to ${escapeHtml(nodeData[currentNode].name)}</div>`;
            term.innerHTML += `<span style="color:var(--cyan)">root@${escapeHtml(nodeData[currentNode].country || 'xx')}:~#</span> ${escapeHtml(currentTool)} ${safeTarget}\n`; 
            term.innerHTML += `> Initiating ${escapeHtml(currentTool)}...\n\n`; term.scrollTop = term.scrollHeight;
            try {
                const formData = new FormData(); formData.append('action', 'run_tool'); formData.append('node_id', currentNode); formData.append('tool', currentTool); formData.append('target', rawTarget); formData.append('proto', currentProto);
                const response = await fetch('api.php', { method: 'POST', body: formData });
                const text = await response.text();
                
                if (text.startsWith('{') && text.includes('"status":"error"')) {
                    const json = JSON.parse(text);
                     term.innerHTML += `<span style="color:var(--pink)">Error: ${escapeHtml(json.message)}</span>\n`;
                } else {
                     term.innerHTML += `<span style="color:#eee">${escapeHtml(text)}</span>\n`; 
                     term.innerHTML += `\n> Done.\n`;
                }
            } catch (e) { term.innerHTML += `<span style="color:var(--pink)">System Error: ${escapeHtml(e.message)}</span>\n`; }
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
                    sitekey: '<?php echo e($cfSiteKey); ?>', 
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
                    if (node.ipv4) downloadUrl = `http://${node.ipv4}/1gb.bin`;
                } else {
                    if (node.ipv6) {
                        let v6 = node.ipv6;
                        if (v6.indexOf(':') > -1 && v6.indexOf('[') === -1) v6 = `[${v6}]`;
                        downloadUrl = `http://${v6}/1gb.bin`;
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
