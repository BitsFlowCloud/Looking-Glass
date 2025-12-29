<?php 
// ==============================================================
// 1. 核心逻辑 (完全保留，未做任何修改)
// ==============================================================
$config = [];
if (file_exists('config.php')) {
    $config = require 'config.php';
}

// 定义变量
$siteTitle = $config['site_title'] ?? 'BitsFlowCloud Looking Glass';
$siteHeader = $config['site_header'] ?? 'BitsFlowCloud Looking Glass';
$footerText = $config['footer_text'] ?? '&copy; 2023-2025 BitsFlowCloud Network. All Rights Reserved.';
$cfSiteKey = $config['cf_site_key'] ?? '';

// Turnstile 开关
$enableTurnstile = $config['enable_turnstile'] ?? true; 

// 安全输出函数
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
    
    <?php if ($enableTurnstile): ?>
    <script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script>
    <?php endif; ?>

    <style>
        :root { 
            --cyan: #00f3ff; 
            --purple: #bc13fe; 
            --green: #00ff9d; 
            --pink: #ff00de; 
            --yellow: #f1c40f; 
            --bg-color: #050505; 
            --text-main: #e0e6ed; 
            --text-dim: #8892b0; 
            --modal-bg: #111; 
            --card-border: rgba(255,255,255,0.1);
            --panel-bg: rgba(15, 15, 15, 0.7);
        }
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { background-color: var(--bg-color); color: var(--text-main); font-family: 'JetBrains Mono', monospace; min-height: 100vh; display: flex; flex-direction: column; align-items: center; overflow-x: hidden; position: relative; user-select: none; }
        #bgCanvas { position: fixed; top: 0; left: 0; width: 100%; height: 100%; z-index: -1; }
        
        /* 标题动画 */
        .header { margin-top: 3rem; margin-bottom: 2rem; text-align: center; position: relative; z-index: 2; }
        .glitch-title { font-family: 'Share Tech Mono', monospace; font-size: 4rem; font-weight: bold; text-transform: uppercase; color: #fff; position: relative; letter-spacing: 4px; text-shadow: 2px 2px 0px var(--cyan); animation: glitch-skew 3s infinite linear alternate-reverse; }
        .glitch-title::before, .glitch-title::after { content: attr(data-text); position: absolute; top: 0; left: 0; width: 100%; height: 100%; }
        .glitch-title::before { left: 2px; text-shadow: -1px 0 var(--purple); clip: rect(44px, 450px, 56px, 0); animation: glitch-anim 5s infinite linear alternate-reverse; }
        .glitch-title::after { left: -2px; text-shadow: -1px 0 var(--cyan); clip: rect(44px, 450px, 56px, 0); animation: glitch-anim2 5s infinite linear alternate-reverse; }
        @keyframes glitch-anim { 0% { clip: rect(31px, 9999px, 91px, 0); } 20% { clip: rect(6px, 9999px, 86px, 0); } 40% { clip: rect(68px, 9999px, 11px, 0); } 100% { clip: rect(82px, 9999px, 2px, 0); } }
        @keyframes glitch-anim2 { 0% { clip: rect(81px, 9999px, 9px, 0); } 20% { clip: rect(7px, 9999px, 88px, 0); } 40% { clip: rect(18px, 9999px, 31px, 0); } 100% { clip: rect(32px, 9999px, 52px, 0); } }
        @keyframes glitch-skew { 0% { transform: skew(0deg); } 10% { transform: skew(-1deg); } 20% { transform: skew(1deg); } 100% { transform: skew(0deg); } }
        
        /* 节点选择器 */
        .region-selector { margin-bottom: 1.5rem; position: relative; z-index: 50; width: 450px; display: flex; flex-direction: column; gap: 10px; }
        .custom-select { position: relative; font-family: 'JetBrains Mono', monospace; font-size: 1.1rem; }
        .select-selected { 
            background: rgba(20, 20, 20, 0.8); 
            border: 1px solid var(--cyan); 
            color: #fff; 
            padding: 12px 20px; 
            cursor: pointer; 
            display: flex; align-items: center; justify-content: center; 
            transition: 0.3s; 
            border-radius: 4px; 
            box-shadow: 0 0 10px rgba(0, 243, 255, 0.1);
        }
        .select-selected:hover { background: rgba(0, 243, 255, 0.1); box-shadow: 0 0 20px rgba(0, 243, 255, 0.3); }
        .select-selected::after {
            content: ""; position: absolute; right: 20px; top: 45%; width: 0; height: 0; 
            border-left: 6px solid transparent; border-right: 6px solid transparent; border-top: 8px solid var(--cyan); 
            transition: transform 0.3s;
        }
        .select-selected.select-arrow-active::after { transform: rotate(180deg); }
        .select-items { position: absolute; background-color: #000; border: 1px solid var(--cyan); top: 100%; left: 0; right: 0; z-index: 99; margin-top: 5px; max-height: 400px; overflow-y: auto; box-shadow: 0 10px 30px rgba(0,0,0,0.8); }
        .select-hide { display: none; }
        .select-item { padding: 12px 25px; cursor: pointer; border-bottom: 1px solid rgba(255,255,255,0.1); display: flex; align-items: center; justify-content: center; color: #ccc; transition: all 0.2s; }
        .select-item:hover { background: rgba(0, 243, 255, 0.2); color: #fff; }
        .flag-icon { width: 24px; height: 18px; margin-right: 15px; vertical-align: middle; border-radius: 2px; }
        
        /* 主布局 */
        .main-container { width: 95%; max-width: 900px; display: flex; flex-direction: column; gap: 20px; margin-bottom: 30px; position: relative; z-index: 5; }
        
        .glass-card { 
            background: var(--panel-bg); 
            backdrop-filter: blur(10px);
            border-radius: 12px; 
            padding: 20px; 
            border: 1px solid var(--card-border); 
            box-shadow: 0 10px 30px rgba(0,0,0,0.5); 
            display: flex; flex-direction: column;
        }
        
        .card-title { font-size: 1rem; margin-bottom: 15px; font-weight: bold; padding-bottom: 8px; letter-spacing: 2px; text-transform: uppercase; border-bottom: 1px solid var(--card-border); color: var(--text-dim); display: flex; justify-content: space-between; align-items: center; }

        /* IP 显示颜色与复制 */
        .ip-display-row { display: flex; justify-content: space-between; margin-bottom: 5px; font-size: 0.8rem; font-weight: bold; letter-spacing: 1px; }
        .text-v4 { color: var(--cyan); text-shadow: 0 0 5px rgba(0,243,255,0.3); }
        .text-v6 { color: var(--purple); text-shadow: 0 0 5px rgba(188,19,254,0.3); }

        .ip-value-row { display: flex; justify-content: space-between; margin-bottom: 15px; font-family: 'JetBrains Mono'; font-size: 0.95rem; word-break: break-all; gap: 10px; }
        
        .ip-val { 
            cursor: pointer; 
            border-bottom: 1px dotted #333; 
            transition: all 0.2s; 
            padding-bottom: 2px;
        }
        .ip-val.v4-color { color: var(--cyan); }
        .ip-val.v4-color:hover { background: rgba(0, 243, 255, 0.1); border-bottom: 1px solid var(--cyan); }
        
        .ip-val.v6-color { color: var(--purple); }
        .ip-val.v6-color:hover { background: rgba(188, 19, 254, 0.1); border-bottom: 1px solid var(--purple); }

        .command-deck { background: rgba(0,0,0,0.3); padding: 15px; border-radius: 8px; border: 1px solid var(--card-border); margin-bottom: 15px; }
        .deck-label { font-size: 0.7rem; color: var(--cyan); margin-bottom: 8px; letter-spacing: 1px; font-weight: bold; }
        
        .target-input { width: 100%; background: #111; border: 1px solid #333; color: #fff; padding: 10px; font-family: 'JetBrains Mono'; margin-bottom: 10px; border-radius: 4px; outline: none; transition: 0.3s; }
        .target-input:focus { border-color: var(--cyan); box-shadow: 0 0 10px rgba(0,243,255,0.1); }

        .proto-switch { display: flex; gap: 2px; margin-bottom: 10px; background: #111; padding: 2px; border-radius: 4px; }
        .proto-btn { flex: 1; background: transparent; border: none; color: #666; padding: 6px; cursor: pointer; font-weight: bold; font-size: 0.8rem; transition: 0.2s; border-radius: 2px; }
        .proto-btn.active.v4 { background: var(--cyan); color: #000; }
        .proto-btn.active.v6 { background: var(--purple); color: #fff; }

        .tools-grid { display: grid; grid-template-columns: 1fr 1fr 1fr 1fr; gap: 8px; }
        .tool-btn { 
            background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.1); color: #ccc; 
            padding: 10px; cursor: pointer; font-family: 'Share Tech Mono'; font-size: 0.9rem; 
            transition: 0.2s; text-transform: uppercase; border-radius: 4px;
        }
        .tool-btn:hover { background: var(--cyan); color: #000; border-color: var(--cyan); box-shadow: 0 0 10px rgba(0,243,255,0.3); }
        .tool-btn:active { transform: scale(0.98); }

        .dl-group { display: flex; gap: 10px; margin-top: 10px; }
        .btn-dl-mini { flex: 1; padding: 8px; border: 1px solid #333; background: #111; color: #888; cursor: pointer; font-size: 0.75rem; transition: 0.2s; border-radius: 4px; }
        .btn-dl-mini:hover { border-color: #fff; color: #fff; }

        /* 控制台高度 */
        .terminal-output { 
            background: #000; 
            border: 1px solid #333; 
            color: #ccc; 
            padding: 12px; 
            font-size: 0.8rem; 
            height: 260px; 
            overflow-y: auto; 
            border-radius: 4px; 
            white-space: pre-wrap; 
            font-family: 'Consolas', monospace;
        }

        /* 流媒体横向布局 */
        .monitor-container {
            display: flex;
            min-height: 120px; 
            background: rgba(0,0,0,0.3);
            border-radius: 8px;
            overflow: hidden;
            border: 1px solid var(--card-border);
        }
        
        .monitor-tabs {
            width: 40px;
            display: flex;
            flex-direction: column;
            border-right: 1px solid var(--card-border);
        }
        .m-tab {
            flex: 1;
            border: none;
            background: #0a0a0a;
            color: #555;
            cursor: pointer;
            font-weight: bold;
            font-size: 0.75rem;
            writing-mode: vertical-rl;
            text-orientation: mixed;
            transform: rotate(180deg);
            transition: all 0.2s;
        }
        .m-tab:hover { background: #151515; color: #888; }
        
        .m-tab.active.v4 { background: rgba(0, 243, 255, 0.1); color: var(--cyan); border-right: 3px solid var(--cyan); }
        .m-tab.active.v6 { background: rgba(188, 19, 254, 0.1); color: var(--purple); border-right: 3px solid var(--purple); }

        .monitor-content {
            flex: 1;
            padding: 10px;
            overflow: hidden; 
        }
        
        /* 强制 3 列布局 */
        .h-grid {
            display: grid;
            grid-template-columns: repeat(3, 1fr); 
            gap: 10px;
        }
        
        .h-item {
            background: rgba(255,255,255,0.05);
            padding: 8px 10px;
            border-radius: 4px;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            border: 1px solid transparent;
        }
        .h-item:hover { background: rgba(255,255,255,0.1); border-color: rgba(255,255,255,0.1); }
        
        .h-label { font-size: 0.65rem; color: var(--text-dim); text-transform: uppercase; margin-bottom: 4px; }
        .h-val { font-family: 'JetBrains Mono'; font-size: 0.8rem; text-align: center; white-space: nowrap; display: flex; align-items: center; justify-content: center; }

        /* === 新增：状态标志图片样式 === */
        .status-flag {
            height: 14px;
            width: auto;
            border-radius: 2px;
            margin-left: 6px;
            vertical-align: middle;
            box-shadow: 0 0 2px rgba(0,0,0,0.5);
        }

        /* 状态颜色 */
        .status-yes { color: var(--green); font-weight: bold; text-shadow: 0 0 5px rgba(0,255,157,0.2); }
        .status-warn { color: var(--yellow); font-weight: bold; font-size: 0.75rem; }
        .status-no { color: #666; font-weight: bold; }
        .status-na { color: #444; font-size: 0.7rem; }
        
        /* 模态框 */
        .modal-overlay { position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.8); z-index: 100; display: none; justify-content: center; align-items: center; backdrop-filter: blur(5px); }
        .modal { background: #111; border: 1px solid #333; padding: 30px; border-radius: 12px; width: 450px; text-align: center; box-shadow: 0 0 50px rgba(0,0,0,0.8); }
        .btn-close { background: transparent; border: none; color: #666; margin-top: 20px; cursor: pointer; text-decoration: underline; }

        footer { margin-top: auto; padding: 20px; font-size: 0.8rem; color: rgba(255,255,255,0.2); z-index: 5; }
        
        /* Toast 样式 */
        .toast { 
            position: fixed; 
            bottom: 30px; 
            left: 50%; 
            transform: translateX(-50%);
            background: rgba(0, 255, 157, 0.95); 
            color: #000; 
            padding: 10px 30px; 
            border-radius: 4px; 
            font-weight: bold; 
            display: none; 
            z-index: 200; 
            box-shadow: 0 0 20px rgba(0, 255, 157, 0.5);
            font-family: 'Share Tech Mono';
            letter-spacing: 2px;
            animation: fadeInOut 2s ease-in-out;
        }
        @keyframes fadeInOut {
            0% { opacity: 0; transform: translate(-50%, 20px); }
            10% { opacity: 1; transform: translate(-50%, 0); }
            90% { opacity: 1; transform: translate(-50%, 0); }
            100% { opacity: 0; transform: translate(-50%, -20px); }
        }
    </style>
</head>
<body>

    <canvas id="bgCanvas"></canvas>

    <div class="header">
        <div class="glitch-title" data-text="<?php echo e($siteHeader); ?>"><?php echo e($siteHeader); ?></div>
        <div style="font-size: 0.9rem; color: var(--cyan); margin-top: 10px; letter-spacing: 3px; opacity: 0.7;">NETWORK DIAGNOSTIC TOOL</div>
    </div>

    <!-- 节点选择器 -->
    <div class="region-selector">
        <div class="custom-select" id="customNodeSelect">
            <div class="select-selected" id="currentSelectDisplay" onclick="toggleSelect()">
                <span style="color:#888;">Loading nodes...</span>
            </div>
            <div class="select-items select-hide" id="customOptions"></div>
        </div>
    </div>

    <div class="main-container">
        
        <!-- 上部分：指挥台与终端 -->
        <div class="glass-card">
            <div class="card-title">
                <span>COMMAND DECK</span>
            </div>

            <!-- IP 信息 -->
            <div class="ip-display-row">
                <span class="text-v4">IPv4 ADDRESS</span>
                <span class="text-v6">IPv6 ADDRESS</span>
            </div>
            <div class="ip-value-row">
                <span id="ipv4-addr" class="ip-val v4-color" onclick="copyIp('ipv4-addr')">--</span>
                <span id="ipv6-addr" class="ip-val v6-color" onclick="copyIp('ipv6-addr')">--</span>
            </div>

            <!-- 工具栏 -->
            <div class="command-deck">
                <div class="deck-label">TARGET ADDRESS</div>
                <input type="text" id="target-input-main" class="target-input" placeholder="IP or Domain">
                
                <div class="deck-label">PROTOCOL</div>
                <div class="proto-switch">
                    <button class="proto-btn active v4" onclick="setProto('IPv4')" id="btn-p-v4">IPv4</button>
                    <button class="proto-btn" onclick="setProto('IPv6')" id="btn-p-v6">IPv6</button>
                </div>

                <div class="deck-label">EXECUTE TOOL</div>
                <div class="tools-grid">
                    <button class="tool-btn" onclick="runDirectTool('ping')">PING</button>
                    <button class="tool-btn" onclick="runDirectTool('mtr')">MTR</button>
                    <button class="tool-btn" onclick="runDirectTool('route')">ROUTE</button>
                    <button class="tool-btn" onclick="runDirectTool('iperf3')">IPERF3</button>
                </div>
            </div>

            <div class="terminal-output" id="terminal">[System] Ready. Select a node to begin.</div>

            <div class="dl-group">
                <button class="btn-dl-mini" onclick="initFileTest('IPv4')">⬇ DL Test (IPv4)</button>
                <button class="btn-dl-mini" onclick="initFileTest('IPv6')">⬇ DL Test (IPv6)</button>
            </div>
        </div>

        <!-- 下部分：极度紧凑横向流媒体监控 -->
        <div class="glass-card" style="padding: 15px;">
            <div class="card-title" style="margin-bottom: 10px; font-size: 0.9rem;">
                <span>UNLOCK MONITOR</span>
            </div>
            
            <div class="monitor-container">
                <!-- 左侧标签 -->
                <div class="monitor-tabs">
                    <button class="m-tab active v4" onclick="switchStreamTab('v4')" id="tab-v4">IPv4</button>
                    <button class="m-tab" onclick="switchStreamTab('v6')" id="tab-v6">IPv6</button>
                </div>
                <!-- 右侧内容 -->
                <div class="monitor-content">
                    <div id="stream-v4" class="h-grid">
                        <div style="color:#666; font-size:0.8rem; grid-column: 1 / -1; text-align: center;">Loading...</div>
                    </div>
                    <div id="stream-v6" class="h-grid" style="display:none;"></div>
                </div>
            </div>
        </div>
    </div>

    <footer><?php echo $footerText; ?></footer>
    
    <!-- 复制成功提示 -->
    <div id="copyToast" class="toast">COPIED TO CLIPBOARD</div>

    <!-- 模态框 -->
    <div class="modal-overlay" id="modal-cf">
        <div class="modal" style="width: 400px; padding: 20px;">
            <h3 style="font-size:1.2rem;">SECURITY CHECK</h3>
            <div id="cf-widget-container" style="display:flex; justify-content:center; margin:20px 0;"></div>
            <div id="cf-status" style="color:#888; font-size:0.8rem;">Please complete the check.</div>
            <button class="btn-close" onclick="closeAllModals()">Cancel</button>
        </div>
    </div>

    <div class="modal-overlay" id="modal-message">
        <div class="modal">
            <h3 id="msg-title">NOTICE</h3>
            <div id="msg-body" style="color:#ccc; margin-bottom:20px;"></div>
            <button class="tool-btn" style="width:100px; margin:0 auto;" onclick="closeMsgModal()">OK</button>
        </div>
    </div>

    <script>
        // 背景动画
        const canvas = document.getElementById('bgCanvas'); const ctx = canvas.getContext('2d');
        let width, height; let particles = [];
        function initCanvas() { width = canvas.width = window.innerWidth; height = canvas.height = window.innerHeight; particles = []; for(let i=0; i<100; i++) particles.push({ x: Math.random()*width, y: Math.random()*height, z: Math.random()*2+0.5, size: Math.random()*2 }); }
        function drawCanvas() { ctx.fillStyle = '#050505'; ctx.fillRect(0, 0, width, height); ctx.fillStyle = '#00f3ff'; particles.forEach(p => { p.y += p.z * 0.5; if(p.y > height) { p.y = 0; p.x = Math.random() * width; } ctx.globalAlpha = (p.z - 0.5) / 2 * 0.5; ctx.beginPath(); ctx.arc(p.x, p.y, p.size, 0, Math.PI*2); ctx.fill(); }); ctx.globalAlpha = 1; requestAnimationFrame(drawCanvas); }
        window.addEventListener('resize', initCanvas); initCanvas(); drawCanvas();

        // 逻辑变量
        let nodeData = {}; let selectedProto = 'IPv4'; let currentNode = null; let limitInterval = null; let turnstileWidgetId = null; let pendingDownloadProto = null;
        const useTurnstile = <?php echo $enableTurnstile ? 'true' : 'false'; ?>;
        const cfSiteKey = "<?php echo $cfSiteKey; ?>";

        function escapeHtml(text) { if (!text) return text; return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#039;"); }

        // 初始化
        async function initCustomDropdown() {
            fetch('https://api.ipify.org?format=json').then(r=>r.json()).then(d=>{ document.getElementById('target-input-main').value = d.ip; }).catch(e=>{});

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

        function toggleSelect() { 
            document.getElementById("customOptions").classList.toggle("select-hide"); 
            document.getElementById("currentSelectDisplay").classList.toggle("select-arrow-active");
        }
        function updateSelected(key, name, flag, close = true) {
            document.getElementById("currentSelectDisplay").innerHTML = `<span style="display:flex; align-items:center; overflow:hidden; text-overflow:ellipsis;"><img src="https://flagcdn.com/24x18/${escapeHtml(flag.toLowerCase())}.png" class="flag-icon"> ${escapeHtml(name)}</span>`;
            currentNode = key; switchNode();
            if(close) {
                document.getElementById("customOptions").classList.add("select-hide");
                document.getElementById("currentSelectDisplay").classList.remove("select-arrow-active");
            }
        }
        window.onclick = function(e) { if (!e.target.matches('.select-selected') && !e.target.matches('.select-selected *')) { const myDropdown = document.getElementById("customOptions"); if (!myDropdown.classList.contains('select-hide')) { myDropdown.classList.add('select-hide'); document.getElementById("currentSelectDisplay").classList.remove("select-arrow-active"); } } }

        function switchNode() {
            if (!currentNode || !nodeData[currentNode]) return;
            const data = nodeData[currentNode];
            document.getElementById('ipv4-addr').innerText = data.ipv4 || data.ip4 || '--'; 
            document.getElementById('ipv6-addr').innerText = data.ipv6 || data.ip6 || '--';
            
            const term = document.getElementById('terminal');
            term.innerHTML = `<div style="margin-bottom:10px; color:#888;">[System] Connected to ${escapeHtml(data.name)}</div>`;
            
            // 渲染流媒体
            let v4Data = (data.unlock && data.unlock.v4) ? data.unlock.v4 : (data.unlock || {});
            let v6Data = (data.unlock && data.unlock.v6) ? data.unlock.v6 : {};
            
            renderStreamTabs(v4Data, v6Data);
        }

        function setProto(p) {
            selectedProto = p;
            document.getElementById('btn-p-v4').className = p === 'IPv4' ? 'proto-btn active v4' : 'proto-btn';
            document.getElementById('btn-p-v6').className = p === 'IPv6' ? 'proto-btn active v6' : 'proto-btn';
        }

        function copyIp(id) {
            const txt = document.getElementById(id).innerText;
            if(txt === '--' || txt === 'N/A') return;
            if (navigator.clipboard && window.isSecureContext) {
                navigator.clipboard.writeText(txt).then(showToast).catch(err => fallbackCopy(txt));
            } else { fallbackCopy(txt); }
        }

        function fallbackCopy(text) {
            let textArea = document.createElement("textarea"); textArea.value = text;
            textArea.style.position = "fixed"; textArea.style.left = "-9999px";
            document.body.appendChild(textArea); textArea.focus(); textArea.select();
            try { document.execCommand('copy'); showToast(); } catch (err) {}
            document.body.removeChild(textArea);
        }

        function showToast() {
            const t = document.getElementById('copyToast'); t.style.display = 'block';
            setTimeout(() => { t.style.display = 'none'; }, 2000);
        }

        function switchStreamTab(ver) {
            document.getElementById('stream-v4').style.display = ver === 'v4' ? 'grid' : 'none';
            document.getElementById('stream-v6').style.display = ver === 'v6' ? 'grid' : 'none';
            document.getElementById('tab-v4').className = ver === 'v4' ? 'm-tab active v4' : 'm-tab';
            document.getElementById('tab-v6').className = ver === 'v6' ? 'm-tab active v6' : 'm-tab';
        }

        function renderStreamTabs(v4Data, v6Data) {
            fillGrid('stream-v4', v4Data);
            fillGrid('stream-v6', v6Data);
            switchStreamTab('v4');
        }

        function fillGrid(elementId, data) {
            const container = document.getElementById(elementId);
            const services = ['Netflix', 'YouTube', 'Disney+', 'TikTok', 'Spotify', 'Gemini'];
            let html = '';
            
            services.forEach(s => {
                const key = s.toLowerCase().replace('+','');
                const valHtml = getStatusHtml(data ? data[key] : 'N/A');
                
                html += `
                    <div class="h-item">
                        <div class="h-label">${s}</div>
                        <div class="h-val">${valHtml}</div>
                    </div>
                `;
            });
            container.innerHTML = html;
        }

        // === 修改点：自动显示国旗图标 ===
        function getStatusHtml(rawText) {
            if (!rawText) return '<span class="status-na">N/A</span>';
            const text = rawText.toString();
            const lower = text.toLowerCase();
            let html = '';
            
            // 提取地区代码
            let regionCode = null;
            const regMatch = text.match(/Region:\s*([A-Za-z]{2})/i);
            if (regMatch) {
                regionCode = regMatch[1];
            } else if (text.includes('[')) {
                const simpleMatch = text.match(/\[([A-Z]{2})\]/);
                if (simpleMatch) regionCode = simpleMatch[1];
            }

            // 生成国旗图标 HTML
            let flagHtml = '';
            if (regionCode) {
                flagHtml = `<img src="https://flagcdn.com/24x18/${regionCode.toLowerCase()}.png" class="status-flag" alt="${regionCode}">`;
            }

            if (lower.includes('originals')) html = `<span class="status-warn">ORIGINALS ONLY</span>${flagHtml}`;
            else if (lower.includes('yes')) html = `<span class="status-yes">YES</span>${flagHtml}`;
            else if (lower.includes('no') || lower.includes('block')) html = `<span class="status-no">NO</span>`;
            else if (lower.includes('error')) html = `<span class="status-na">ERR</span>`;
            else html = `<span class="status-na">${escapeHtml(text)}</span>`;
            return html;
        }

        async function runDirectTool(tool) {
            if (!currentNode) { showCustomAlert("Please select a node first."); return; }
            const target = document.getElementById('target-input-main').value.trim();
            if (!target) { showCustomAlert("Please enter a target IP or Domain."); return; }

            if (tool === 'iperf3') {
                showIperfCommand(target);
                return;
            }

            const term = document.getElementById('terminal');
            term.innerHTML += `\n<span style="color:var(--cyan)">root@${escapeHtml(nodeData[currentNode].country || 'xx')}:~#</span> ${escapeHtml(tool)} ${escapeHtml(target)} [${selectedProto}]\n`; 
            term.innerHTML += `> Running...\n`; term.scrollTop = term.scrollHeight;

            try {
                const formData = new FormData(); 
                formData.append('action', 'run_tool'); 
                formData.append('node_id', currentNode); 
                formData.append('tool', tool); 
                formData.append('target', target); 
                formData.append('proto', selectedProto);
                
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

        async function showIperfCommand(target) {
             showCustomAlert("Requesting server resource...", "PLEASE WAIT");
             try {
                const formData = new FormData(); formData.append('action', 'run_tool'); formData.append('node_id', currentNode); formData.append('tool', 'iperf3'); formData.append('target', '0.0.0.0'); formData.append('proto', selectedProto);
                const response = await fetch('api.php', { method: 'POST', body: formData });
                const text = await response.text();
                if (text.includes("iperf3 -c")) {
                    const cmd = text.trim();
                    showCustomAlert(
                        `<div style="background:#222; padding:15px; border-radius:5px; color:#00ff9d; font-family:monospace; word-break:break-all; border:1px solid #444; margin-bottom:10px;">${cmd}</div>
                         <div style="color:#f1c40f; font-size:0.85rem; font-weight:bold; letter-spacing:1px;">⚠️ Port valid for 60 seconds.</div>`, 
                        `IPERF3 SESSION (${selectedProto})`
                    );
                } else { showCustomAlert("Error: " + escapeHtml(text), "ERROR"); }
             } catch(e) { showCustomAlert("Net Error", "ERROR"); }
        }

        function showCustomAlert(msg, title = "NOTICE") { document.getElementById('msg-title').innerText = title; document.getElementById('msg-body').innerHTML = msg; document.getElementById('modal-message').style.display = 'flex'; }
        function closeMsgModal() { document.getElementById('modal-message').style.display = 'none'; }
        function closeAllModals() { document.getElementById('modal-cf').style.display = 'none'; document.getElementById('modal-message').style.display = 'none'; }

        function initFileTest(proto) {
            if (!currentNode) return;

            pendingDownloadProto = proto;
            if (useTurnstile) {
                document.getElementById('modal-cf').style.display = 'flex';
                document.getElementById('cf-status').innerText = "Verifying...";
                if (turnstileWidgetId === null) {
                    turnstileWidgetId = turnstile.render('#cf-widget-container', {
                        sitekey: cfSiteKey, theme: 'light',
                        callback: function(token) { setTimeout(() => { closeAllModals(); startDownload(); }, 500); }
                    });
                } else { turnstile.reset(turnstileWidgetId); }
            } else { startDownload(); }
        }

        function startDownload() {
            const node = nodeData[currentNode];
            let url = '';
            if (pendingDownloadProto === 'IPv4' && node.ipv4) url = `http://${node.ipv4}/1gb.bin`;
            else if (pendingDownloadProto === 'IPv6' && node.ipv6) {
                let v6 = node.ipv6; if (v6.indexOf(':') > -1 && v6.indexOf('[') === -1) v6 = `[${v6}]`;
                url = `http://${v6}/1gb.bin`;
            }
            if(url) window.open(url, '_blank', 'noopener,noreferrer');
            else showCustomAlert("IP not configured.", "ERROR");
        }

        window.onload = function() { initCustomDropdown(); };
    </script>
</body>
</html>
