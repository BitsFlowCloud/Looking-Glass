<?php
/**
 * 主控端 API - 负责连接前端与各个节点
 */
error_reporting(0);
header('Content-Type: application/json; charset=utf-8');

// 加载配置
$config = require 'config.php';
$action = $_POST['action'] ?? '';

// === 新增：获取 Turnstile 配置 ===
// 默认为 true (开启)，除非 config.php 里明确写了 false
$enableTurnstile = $config['enable_turnstile'] ?? true;
$cfSecretKey     = $config['cf_secret_key'] ?? '';

// === 1. 获取节点列表 (并抓取流媒体状态) ===
if ($action === 'get_nodes') {
    $nodes = $config['nodes'];
    $final_nodes = [];
    
    foreach ($nodes as $id => $node) {
        $unlock_data = ['v4' => null, 'v6' => null];
        
        $postData = [
            'key'    => $node['key'],
            'action' => 'get_unlock'
        ];
        
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
            if (is_array($json)) {
                $unlock_data = $json;
            }
        }
        
        $node['unlock'] = $unlock_data;
        unset($node['key']);
        unset($node['api_url']);
        
        $final_nodes[$id] = $node;
    }
    echo json_encode(['status' => 'success', 'data' => $final_nodes]);
    exit;
}

// === 2. 运行工具 (Ping/MTR/Iperf3) ===
if ($action === 'run_tool') {
    
    // >>>>>>>>>> Cloudflare Turnstile 验证逻辑开始 <<<<<<<<<<
    if ($enableTurnstile) {
        $token = $_POST['cf-turnstile-response'] ?? '';
        
        // 如果没有 Token 或者 Token 为空
        if (empty($token)) {
            // 注意：如果是 Ping/MTR 这种通常由 JS 触发的，前端需要确保发送了这个 Token
            // 如果前端还没集成 Turnstile 到 Ping 按钮，这里会报错。
            // 建议：如果只是下载文件需要验证，Ping 不需要，可以在 config.php 设置为 false
            echo json_encode(['status' => 'error', 'message' => 'Security check failed: CAPTCHA missing.']);
            exit;
        }

        // 向 Cloudflare 发起验证
        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, "https://challenges.cloudflare.com/turnstile/v0/siteverify");
        curl_setopt($ch, CURLOPT_POST, 1);
        curl_setopt($ch, CURLOPT_POSTFIELDS, http_build_query([
            'secret'   => $cfSecretKey,
            'response' => $token,
            'remoteip' => $_SERVER['REMOTE_ADDR']
        ]));
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        $cf_result = curl_exec($ch);
        curl_close($ch);
        
        $cf_json = json_decode($cf_result, true);
        
        // 验证失败
        if (!$cf_json || !($cf_json['success'] ?? false)) {
            echo json_encode(['status' => 'error', 'message' => 'Security check failed. Please refresh the page.']);
            exit;
        }
    }
    // >>>>>>>>>> Cloudflare Turnstile 验证逻辑结束 <<<<<<<<<<

    $node_id = $_POST['node_id'] ?? '';
    
    if (!isset($config['nodes'][$node_id])) {
        echo json_encode(['status' => 'error', 'message' => 'Node not found']);
        exit;
    }
    $node = $config['nodes'][$node_id];
    
    // 透传所有参数给 Agent
    $postData = $_POST;
    $postData['key'] = $node['key']; // 加上密钥
    
    // 如果开启了验证，发送给 Agent 时可以把 Token 删了，减少包大小(可选)
    unset($postData['cf-turnstile-response']);

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
    
    if ($err) {
        echo "Error connecting to node: $err";
    } elseif ($http_code == 403) {
        echo "Error: Authorization Failed (Check API Key)";
    } else {
        echo $response;
    }
    exit;
}

echo json_encode(['status' => 'error', 'message' => 'Invalid action']);
?>
