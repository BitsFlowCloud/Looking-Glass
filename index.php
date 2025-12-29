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
<html lang="en" data-theme="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title><?php echo e($siteTitle); ?></title>
    <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;700&family=Share+Tech+Mono&display=swap" rel="stylesheet">
    
    <?php if ($enableTurnstile): ?>
    <script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script>
    <?php endif; ?>

    <style>
        /* === 样式定义 === */
        :root { 
            /* 默认暗色主题变量 */
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
            --input-bg: #111;
            --input-border: #333;
            --hover-bg: rgba(255,255,255,0.05);
            --select-bg: rgba(20, 20, 20, 0.8);
            --select-dropdown: #000;
            
            /* 终端专用变量 (暗色) */
            --term-bg: #000;
            --term-text: #ccc;
            --term-border: #333;
        }

        /* === 亮色主题变量 === */
        [data-theme="light"] {
            --bg-color: #f0f2f5;
            --text-main: #1a1a1a;
            --text-dim: #555;
            --modal-bg: #fff;
            --card-border: rgba(0,0,0,0.1);
            --panel-bg: rgba(255, 255, 255, 0.75);
            --input-bg: #fff;
            --input-border: #ccc;
            --hover-bg: rgba(0,0,0,0.05);
            --select-bg: #fff;
            --select-dropdown: #fff;
            
            --cyan: #00a8b0; 
            --purple: #8a0eb8;

            /* 终端专用变量 (亮色) */
            --term-bg: #ffffff;
            --term-text: #1a1a1a;
            --term-border: #ccc;
        }

        * { margin: 0; padding: 0; box-sizing: border-box; }
        
        body { 
            background-color: var(--bg-color); 
            color: var(--text-main); 
            font-family: 'JetBrains Mono', monospace; 
            min-height: 100vh; 
            display: flex; 
            flex-direction: column; 
            align-items: center; 
            overflow-x: hidden; 
            position: relative; 
            user-select: none; 
            transition: background-color 0.3s, color 0.3s; 
            padding-bottom: 10px;
        }
        
        #bgCanvas { position: fixed; top: 0; left: 0; width: 100%; height: 100%; z-index: -1; transition: opacity 0.3s; }
        
        /* 标题动画 */
        .header { margin-top: 2rem; margin-bottom: 1rem; text-align: center; position: relative; z-index: 2; width: 100%; padding: 0 10px; }
        [data-theme="light"] .glitch-title { text-shadow: 2px 2px 0px rgba(0,0,0,0.1); color: #333; }
        
        .glitch-title { 
            font-family: 'Share Tech Mono', monospace; 
            font-size: clamp(2rem, 5vw, 3.5rem);
            font-weight: bold; 
            text-transform: uppercase; 
            color: #fff; 
            position: relative; 
            letter-spacing: 4px; 
            text-shadow: 2px 2px 0px var(--cyan); 
            animation: glitch-skew 3s infinite linear alternate-reverse; 
            transition: color 0.3s; 
            line-height: 1.1;
        }
        
        .glitch-title::before, .glitch-title::after { content: attr(data-text); position: absolute; top: 0; left: 0; width: 100%; height: 100%; }
        .glitch-title::before { left: 2px; text-shadow: -1px 0 var(--purple); clip: rect(44px, 450px, 56px, 0); animation: glitch-anim 5s infinite linear alternate-reverse; }
        .glitch-title::after { left: -2px; text-shadow: -1px 0 var(--cyan); clip: rect(44px, 450px, 56px, 0); animation: glitch-anim2 5s infinite linear alternate-reverse; }
        @keyframes glitch-anim { 0% { clip: rect(31px, 9999px, 91px, 0); } 20% { clip: rect(6px, 9999px, 86px, 0); } 40% { clip: rect(68px, 9999px, 11px, 0); } 100% { clip: rect(82px, 9999px, 2px, 0); } }
        @keyframes glitch-anim2 { 0% { clip: rect(81px, 9999px, 9px, 0); } 20% { clip: rect(7px, 9999px, 88px, 0); } 40% { clip: rect(18px, 9999px, 31px, 0); } 100% { clip: rect(32px, 9999px, 52px, 0); } }
        @keyframes glitch-skew { 0% { transform: skew(0deg); } 10% { transform: skew(-1deg); } 20% { transform: skew(1deg); } 100% { transform: skew(0deg); } }
        
        /* === 控制栏 (节点选择器 + 明暗切换) === */
        .control-bar {
            width: 95%;
            max-width: 980px; /* 修改 2：加宽到 980px */
            display: flex;
            justify-content: center;
            align-items: center;
            gap: 15px;
            margin-bottom: 1.2rem;
            z-index: 50;
            flex-wrap: wrap; 
        }

        /* 节点选择器 */
        .region-selector { 
            position: relative; 
            flex: 1; 
            min-width: 250px;
        }
        .custom-select { position: relative; font-family: 'JetBrains Mono', monospace; font-size: 1rem; }
        .select-selected { 
            background: var(--select-bg); 
            border: 1px solid var(--cyan); 
            color: var(--text-main); 
            padding: 10px 20px; 
            cursor: pointer; 
            display: flex; align-items: center; justify-content: center; 
            transition: 0.3s; 
            border-radius: 12px; /* 修改 1：大圆角 */
            box-shadow: 0 0 10px rgba(0, 243, 255, 0.1);
            height: 42px; 
        }
        .select-selected:hover { background: var(--hover-bg); box-shadow: 0 0 20px rgba(0, 243, 255, 0.3); }
        .select-selected::after {
            content: ""; position: absolute; right: 20px; top: 45%; width: 0; height: 0; 
            border-left: 6px solid transparent; border-right: 6px solid transparent; border-top: 8px solid var(--cyan); 
            transition: transform 0.3s;
        }
        .select-selected.select-arrow-active::after { transform: rotate(180deg); }
        .select-items { position: absolute; background-color: var(--select-dropdown); border: 1px solid var(--cyan); top: 100%; left: 0; right: 0; z-index: 99; margin-top: 5px; max-height: 300px; overflow-y: auto; box-shadow: 0 10px 30px rgba(0,0,0,0.5); border-radius: 12px; /* 修改 1：大圆角 */ }
        .select-hide { display: none; }
        .select-item { padding: 10px 25px; cursor: pointer; border-bottom: 1px solid var(--card-border); display: flex; align-items: center; justify-content: center; color: var(--text-dim); transition: all 0.2s; font-size: 0.95rem; }
        .select-item:hover { background: var(--hover-bg); color: var(--text-main); }
        
        /* 修改 4：Flag Icon - 圆角矩形样式 */
        .flag-icon { 
            width: 28px; /* 稍微加大 */
            height: 21px; 
            margin-right: 15px; 
            vertical-align: middle; 
            border-radius: 4px; /* 圆角矩形 */
            box-shadow: 0 2px 4px rgba(0,0,0,0.3); /* 阴影 */
            object-fit: cover;
        }

        /* === 胶囊型明暗切换按钮 === */
        .theme-capsule-btn {
            background: var(--panel-bg);
            border: 1px solid var(--cyan);
            color: var(--text-main);
            padding: 0 20px;
            height: 42px; 
            border-radius: 50px; 
            font-family: 'Share Tech Mono', monospace;
            font-size: 0.85rem;
            cursor: pointer;
            display: flex;
            align-items: center;
            gap: 10px;
            transition: all 0.3s;
            box-shadow: 0 0 10px rgba(0, 243, 255, 0.1);
            backdrop-filter: blur(5px);
            white-space: nowrap;
        }
        .theme-capsule-btn:hover {
            background: var(--cyan);
            color: #000;
            box-shadow: 0 0 20px rgba(0, 243, 255, 0.4);
            transform: translateY(-1px);
        }
        .theme-icon-box svg {
            width: 18px;
            height: 18px;
            fill: currentColor;
            vertical-align: middle;
            margin-top: -2px;
        }
        
        /* 主布局 */
        .main-container { width: 95%; max-width: 980px; /* 修改 2：加宽到 980px */ display: flex; flex-direction: column; gap: 15px; margin-bottom: 10px; position: relative; z-index: 5; }
        
        .glass-card { 
            background: var(--panel-bg); 
            backdrop-filter: blur(10px);
            border-radius: 24px; /* 修改 1：大圆角 (统一 24px) */
            padding: 20px; /* 稍微增加 Padding 以匹配大圆角 */
            border: 1px solid var(--card-border); 
            box-shadow: 0 10px 30px rgba(0,0,0,0.1); 
            display: flex; flex-direction: column;
            transition: background 0.3s, border 0.3s;
        }
        
        .card-title { font-size: 0.9rem; margin-bottom: 12px; font-weight: bold; padding-bottom: 6px; letter-spacing: 2px; text-transform: uppercase; border-bottom: 1px solid var(--card-border); color: var(--text-dim); display: flex; justify-content: space-between; align-items: center; }

        /* IP 显示颜色与复制 */
        .ip-display-row { display: flex; justify-content: space-between; margin-bottom: 5px; font-size: 0.75rem; font-weight: bold; letter-spacing: 1px; }
        .text-v4 { color: var(--cyan); text-shadow: 0 0 5px rgba(0,243,255,0.3); }
        .text-v6 { color: var(--purple); text-shadow: 0 0 5px rgba(188,19,254,0.3); }

        .ip-value-row { display: flex; justify-content: space-between; margin-bottom: 12px; font-family: 'JetBrains Mono'; font-size: 0.9rem; word-break: break-all; gap: 10px; }
        
        .ip-val { 
            cursor: pointer; 
            border-bottom: 1px dotted var(--text-dim); 
            transition: all 0.2s; 
            padding-bottom: 2px;
        }
        .ip-val.v4-color { color: var(--cyan); }
        .ip-val.v4-color:hover { background: rgba(0, 243, 255, 0.1); border-bottom: 1px solid var(--cyan); }
        
        .ip-val.v6-color { color: var(--purple); }
        .ip-val.v6-color:hover { background: rgba(188, 19, 254, 0.1); border-bottom: 1px solid var(--purple); }

        .command-deck { 
            background: rgba(0,0,0,0.05); 
            padding: 12px; 
            border-radius: 16px; /* 修改 1：内部框体圆角 */
            border: 1px solid var(--card-border); 
            margin-bottom: 12px; 
        }
        .deck-label { font-size: 0.65rem; color: var(--cyan); margin-bottom: 6px; letter-spacing: 1px; font-weight: bold; }
        
        .target-input { 
            width: 100%; 
            background: var(--input-bg); 
            border: 1px solid var(--input-border); 
            color: var(--text-main); 
            padding: 8px; 
            font-family: 'JetBrains Mono'; 
            margin-bottom: 8px; 
            border-radius: 12px; /* 修改 1：大圆角 */
            outline: none; 
            transition: 0.3s; 
            font-size: 0.9rem; 
        }
        .target-input:focus { border-color: var(--cyan); box-shadow: 0 0 10px rgba(0,243,255,0.1); }

        .proto-switch { 
            display: flex; 
            gap: 2px; 
            margin-bottom: 8px; 
            background: var(--input-bg); 
            padding: 3px; 
            border-radius: 12px; /* 修改 1：大圆角 */
            border: 1px solid var(--input-border); 
        }
        .proto-btn { flex: 1; background: transparent; border: none; color: var(--text-dim); padding: 5px; cursor: pointer; font-weight: bold; font-size: 0.75rem; transition: 0.2s; border-radius: 8px; }
        .proto-btn.active.v4 { background: var(--cyan); color: #000; }
        [data-theme="light"] .proto-btn.active.v4 { color: #fff; }
        .proto-btn.active.v6 { background: var(--purple); color: #fff; }

        .tools-grid { display: grid; grid-template-columns: 1fr 1fr 1fr 1fr; gap: 8px; }
        .tool-btn { 
            background: var(--hover-bg); border: 1px solid var(--card-border); color: var(--text-dim); 
            padding: 8px; cursor: pointer; font-family: 'Share Tech Mono'; font-size: 0.85rem; 
            transition: 0.2s; text-transform: uppercase; 
            border-radius: 12px; /* 修改 1：大圆角 */
        }
        .tool-btn:hover { background: var(--cyan); color: #000; border-color: var(--cyan); box-shadow: 0 0 10px rgba(0,243,255,0.3); }
        [data-theme="light"] .tool-btn:hover { color: #fff; }
        .tool-btn:active { transform: scale(0.98); }

        .dl-group { display: flex; gap: 8px; margin-top: 8px; }
        .btn-dl-mini { flex: 1; padding: 6px; border: 1px solid var(--input-border); background: var(--input-bg); color: var(--text-dim); cursor: pointer; font-size: 0.7rem; transition: 0.2s; border-radius: 10px; /* 修改 1：大圆角 */ }
        .btn-dl-mini:hover { border-color: var(--text-main); color: var(--text-main); }

        /* === 修改 3：拉长输出框高度 50px (230 -> 280px) === */
        .terminal-output { 
            background: var(--term-bg); 
            border: 1px solid var(--term-border); 
            color: var(--term-text); 
            padding: 12px; 
            font-size: 0.75rem; 
            height: 280px; /* 修改 3：增加高度 */
            overflow-y: auto; 
            border-radius: 16px; /* 修改 1：内部框体圆角 */
            white-space: pre-wrap; 
            font-family: 'Consolas', monospace;
            transition: background-color 0.3s, color 0.3s, border-color 0.3s;
        }

        /* 流媒体框 */
        .monitor-container {
            display: flex;
            min-height: 140px; 
            background: rgba(0,0,0,0.05);
            border-radius: 16px; /* 修改 1：内部框体圆角 */
            overflow: hidden;
            border: 1px solid var(--card-border);
        }
        
        .monitor-tabs {
            width: 35px;
            display: flex;
            flex-direction: column;
            border-right: 1px solid var(--card-border);
        }
        .m-tab {
            flex: 1;
            border: none;
            background: var(--input-bg);
            color: var(--text-dim);
            cursor: pointer;
            font-weight: bold;
            font-size: 0.7rem;
            writing-mode: vertical-rl;
            text-orientation: mixed;
            transform: rotate(180deg);
            transition: all 0.2s;
        }
        .m-tab:hover { background: var(--hover-bg); color: var(--text-main); }
        
        .m-tab.active.v4 { background: rgba(0, 243, 255, 0.1); color: var(--cyan); border-right: 3px solid var(--cyan); }
        .m-tab.active.v6 { background: rgba(188, 19, 254, 0.1); color: var(--purple); border-right: 3px solid var(--purple); }

        .monitor-content {
            flex: 1;
            padding: 10px; 
            overflow: hidden; 
        }
        
        .h-grid {
            display: grid;
            grid-template-columns: repeat(2, 1fr); 
            gap: 10px; 
        }
        
        .h-item {
            background: var(--hover-bg);
            padding: 10px 12px; 
            border-radius: 12px; /* 修改 1：内部框体圆角 */
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            border: 1px solid transparent;
        }
        .h-item:hover { background: rgba(255,255,255,0.1); border-color: rgba(255,255,255,0.1); }
        
        .h-label { 
            font-size: 0.75rem; 
            color: var(--text-dim); 
            text-transform: uppercase; 
            margin-bottom: 5px; 
        }
        .h-val { 
            font-family: 'JetBrains Mono'; 
            font-size: 0.95rem; 
            text-align: center; 
            white-space: nowrap; 
            display: flex; 
            align-items: center; 
            justify-content: center; 
        }

        /* === 修改 4：Flag Icon - 状态标圆角矩形样式 === */
        .status-flag {
            height: 16px; /* 稍微加大 */
            width: auto;
            border-radius: 4px; /* 圆角矩形 */
            margin-left: 6px;
            vertical-align: middle;
            box-shadow: 0 0 3px rgba(0,0,0,0.4);
        }

        /* 状态颜色 */
        .status-yes { color: var(--green); font-weight: bold; text-shadow: 0 0 5px rgba(0,255,157,0.2); }
        [data-theme="light"] .status-yes { color: #00b36b; text-shadow: none; }
        
        .status-warn { color: var(--yellow); font-weight: bold; font-size: 0.75rem; }
        [data-theme="light"] .status-warn { color: #d4a000; }

        .status-no { color: #666; font-weight: bold; }
        .status-na { color: #888; font-size: 0.7rem; }
        
        /* 模态框 */
        .modal-overlay { position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.8); z-index: 100; display: none; justify-content: center; align-items: center; backdrop-filter: blur(5px); }
        .modal { 
            background: var(--modal-bg); 
            border: 1px solid var(--card-border); 
            padding: 30px; 
            border-radius: 24px; /* 修改 1：大圆角 */
            width: 450px; 
            text-align: center; 
            box-shadow: 0 0 50px rgba(0,0,0,0.5); 
            color: var(--text-main); 
        }
        .btn-close { background: transparent; border: none; color: var(--text-dim); margin-top: 20px; cursor: pointer; text-decoration: underline; }

        /* Footer 样式 */
        footer { 
            margin-top: auto; 
            width: 100%; 
            max-width: 980px; /* 修改 2：加宽到 980px */
            text-align: center;
            padding: 10px 0; 
            font-size: 0.75rem; 
            color: var(--text-dim); 
            z-index: 5; 
            opacity: 0.6; 
        }
        
        /* Toast 样式 */
        .toast { 
            position: fixed; 
            bottom: 30px; 
            left: 50%; 
            transform: translateX(-50%);
            background: rgba(0, 255, 157, 0.95); 
            color: #000; 
            padding: 10px 30px; 
            border-radius: 12px; /* 修改 1：大圆角 */
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

        /* 移动端适配 */
        @media (max-width: 768px) {
            .header { margin-top: 1rem; }
            .control-bar { flex-direction: column; align-items: stretch; gap: 10px; }
            .theme-capsule-btn { justify-content: center; }
            .h-grid { grid-template-columns: repeat(2, 1fr); }
            .terminal-output { height: 200px; } 
        }
    </style>
</head>
<body>

    <canvas id="bgCanvas"></canvas>

    <div class="header">
        <div class="glitch-title" data-text="<?php echo e($siteHeader); ?>"><?php echo e($siteHeader); ?></div>
        <div style="font-size: 0.9rem; color: var(--cyan); margin-top: 5px; letter-spacing: 3px; opacity: 0.7;">NETWORK DIAGNOSTIC TOOL</div>
    </div>

    <!-- 控制栏：节点选择器 + 胶囊按钮 -->
    <div class="control-bar">
        <div class="region-selector">
            <div class="custom-select" id="customNodeSelect">
                <div class="select-selected" id="currentSelectDisplay" onclick="toggleSelect()">
                    <span style="color:var(--text-dim);">Loading nodes...</span>
                </div>
                <div class="select-items select-hide" id="customOptions"></div>
            </div>
        </div>

        <button class="theme-capsule-btn" onclick="toggleTheme()" id="themeBtn" title="Toggle Light/Dark Mode">
            <span id="theme-text-label">SWITCH THEME</span>
            <div class="theme-icon-box">
                <svg id="icon-sun" viewBox="0 0 24 24" style="display:none;"><path d="M12 7c-2.76 0-5 2.24-5 5s2.24 5 5 5 5-2.24 5-5-2.24-5-5-5zM2 13h2c.55 0 1-.45 1-1s-.45-1-1-1H2c-.55 0-1 .45-1 1s.45 1 1 1zm18 0h2c.55 0 1-.45 1-1s-.45-1-1-1h-2c-.55 0-1 .45-1 1s.45 1 1 1zM11 2v2c0 .55.45 1 1 1s1-.45 1-1V2c0-.55-.45-1-1-1s-1 .45-1 1zm0 18v2c0 .55.45 1 1 1s1-.45 1-1v-2c0-.55-.45-1-1-1s-1 .45-1 1zM5.99 4.58a.996.996 0 00-1.41 0 .996.996 0 000 1.41l1.06 1.06c.39.39 1.03.39 1.41 0s.39-1.03 0-1.41L5.99 4.58zm12.37 12.37a.996.996 0 00-1.41 0 .996.996 0 000 1.41l1.06 1.06c.39.39 1.03.39 1.41 0a.996.996 0 000-1.41l-1.06-1.06zm1.06-10.96a.996.996 0 000-1.41.996.996 0 00-1.41 0l-1.06 1.06c-.39.39-.39 1.03 0 1.41s1.03.39 1.41 0l1.06-1.06zM7.05 18.36a.996.996 0 000 1.41.996.996 0 001.41 0l1.06-1.06c.39-.39.39-1.03 0-1.41s-1.03-.39-1.41 0l-1.06 1.06z"></path></svg>
                <svg id="icon-moon" viewBox="0 0 24 24"><path d="M12 3c-4.97 0-9 4.03-9 9s4.03 9 9 9 9-4.03 9-9c0-.46-.04-.92-.1-1.36-.98 1.37-2.58 2.26-4.4 2.26-2.98 0-5.4-2.42-5.4-5.4 0-1.81.89-3.42 2.26-4.4-.44-.06-.9-.1-1.36-.1z"></path></svg>
            </div>
        </button>
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
                        <div style="color:var(--text-dim); font-size:0.8rem; grid-column: 1 / -1; text-align: center;">Loading...</div>
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
            <div id="cf-status" style="color:var(--text-dim); font-size:0.8rem;">Please complete the check.</div>
            <button class="btn-close" onclick="closeAllModals()">Cancel</button>
        </div>
    </div>

    <div class="modal-overlay" id="modal-message">
        <div class="modal">
            <h3 id="msg-title">NOTICE</h3>
            <div id="msg-body" style="color:var(--text-dim); margin-bottom:20px;"></div>
            <button class="tool-btn" style="width:100px; margin:0 auto;" onclick="closeMsgModal()">OK</button>
        </div>
    </div>

    <script>
        // === 主题切换逻辑 ===
        function toggleTheme() {
            const html = document.documentElement;
            const current = html.getAttribute('data-theme');
            const next = current === 'light' ? 'dark' : 'light';
            html.setAttribute('data-theme', next);
            localStorage.setItem('theme', next);
            updateThemeIcon(next);
            // 重新绘制背景以适应新颜色
            updateCanvasColor();
        }

        function updateThemeIcon(theme) {
            const label = document.getElementById('theme-text-label');
            if (theme === 'light') {
                document.getElementById('icon-sun').style.display = 'block';
                document.getElementById('icon-moon').style.display = 'none';
                label.innerText = "SWITCH TO DARK";
            } else {
                document.getElementById('icon-sun').style.display = 'none';
                document.getElementById('icon-moon').style.display = 'block';
                label.innerText = "SWITCH TO LIGHT";
            }
        }

        // 初始化主题
        const savedTheme = localStorage.getItem('theme') || 'dark';
        document.documentElement.setAttribute('data-theme', savedTheme);
        updateThemeIcon(savedTheme);

        // === 背景动画 ===
        const canvas = document.getElementById('bgCanvas'); const ctx = canvas.getContext('2d');
        let width, height; let particles = [];
        
        function initCanvas() { width = canvas.width = window.innerWidth; height = canvas.height = window.innerHeight; particles = []; for(let i=0; i<100; i++) particles.push({ x: Math.random()*width, y: Math.random()*height, z: Math.random()*2+0.5, size: Math.random()*2 }); }
        
        // 获取当前 CSS 变量颜色
        function getCssColor(varName) {
            return getComputedStyle(document.documentElement).getPropertyValue(varName).trim();
        }

        function updateCanvasColor() {
            // 强制重绘一帧以应用新背景色 (虽然 CSS 会处理，但粒子颜色需要 JS 更新)
        }

        function drawCanvas() { 
            // 每次绘制都读取当前背景色，实现平滑过渡
            ctx.fillStyle = getCssColor('--bg-color');
            ctx.fillRect(0, 0, width, height); 
            
            // 粒子颜色
            ctx.fillStyle = getCssColor('--cyan'); 
            
            particles.forEach(p => { 
                p.y += p.z * 0.5; 
                if(p.y > height) { p.y = 0; p.x = Math.random() * width; } 
                ctx.globalAlpha = (p.z - 0.5) / 2 * 0.5; 
                ctx.beginPath(); 
                ctx.arc(p.x, p.y, p.size, 0, Math.PI*2); 
                ctx.fill(); 
            }); 
            ctx.globalAlpha = 1; 
            requestAnimationFrame(drawCanvas); 
        }
        
        window.addEventListener('resize', initCanvas); 
        initCanvas(); 
        drawCanvas();

        // 逻辑变量
        let nodeData = {}; let selectedProto = 'IPv4'; let currentNode = null; let limitInterval = null; let turnstileWidgetId = null; let pendingDownloadProto = null;
        const useTurnstile = <?php echo $enableTurnstile ? 'true' : 'false'; ?>;
        const cfSiteKey = "<?php echo $cfSiteKey; ?>";

        function escapeHtml(text) { if (!text) return text; return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#039;"); }

        // 初始化
        async function initCustomDropdown() {
            fetch('https://api.ipify.org?format=json').then(r=>r.json()).then(d=>{ document.getElementById('target-input-main').value = d.ip; }).catch(e=>{});

            const optionsContainer = document.getElementById('customOptions'); 
            optionsContainer.innerHTML = '<div class="select-item" style="color:var(--text-dim);">Loading nodes...</div>';
            try {
                const response = await fetch('api.php', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: 'action=get_nodes' });
                const json = await response.json();
                if (json.status !== 'success') throw new Error(json.message || 'Failed to load nodes');
                
                nodeData = json.data;
                optionsContainer.innerHTML = '';
                const keys = Object.keys(nodeData);
                
                if (keys.length === 0) { document.getElementById("currentSelectDisplay").innerHTML = '<span style="color:var(--text-dim);">No Nodes Configured</span>'; return; }
                
                keys.forEach(key => {
                    const node = nodeData[key]; 
                    const flagCode = node.country || node.flag || 'xx';
                    const div = document.createElement('div'); div.className = 'select-item'; 
                    /* 修改 4：Flag Icon - URL 替换为 w40 以获得高清图 */
                    div.innerHTML = `<span style="display:flex; align-items:center; overflow:hidden; text-overflow:ellipsis;"><img src="https://flagcdn.com/w40/${escapeHtml(flagCode.toLowerCase())}.png" class="flag-icon"> ${escapeHtml(node.name)}</span>`;
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
            /* 修改 4：Flag Icon - URL 替换为 w40 */
            document.getElementById("currentSelectDisplay").innerHTML = `<span style="display:flex; align-items:center; overflow:hidden; text-overflow:ellipsis;"><img src="https://flagcdn.com/w40/${escapeHtml(flag.toLowerCase())}.png" class="flag-icon"> ${escapeHtml(name)}</span>`;
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
            term.innerHTML = `<div style="margin-bottom:10px; color:var(--text-dim);">[System] Connected to ${escapeHtml(data.name)}</div>`;
            
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

        function getStatusHtml(rawText) {
            if (!rawText) return '<span class="status-na">N/A</span>';
            const text = rawText.toString();
            const lower = text.toLowerCase();
            let html = '';
            
            let regionCode = null;
            const regMatch = text.match(/Region:\s*([A-Za-z]{2})/i);
            if (regMatch) {
                regionCode = regMatch[1];
            } else if (text.includes('[')) {
                const simpleMatch = text.match(/\[([A-Z]{2})\]/);
                if (simpleMatch) regionCode = simpleMatch[1];
            }

            let flagHtml = '';
            if (regionCode) {
                /* 修改 4：Flag Icon - URL 替换为 w40 */
                flagHtml = `<img src="https://flagcdn.com/w40/${regionCode.toLowerCase()}.png" class="status-flag" alt="${regionCode}">`;
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
                     // 使用 CSS 变量控制结果文本颜色
                     term.innerHTML += `<span style="color:var(--term-text)">${escapeHtml(text)}</span>\n`; 
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
