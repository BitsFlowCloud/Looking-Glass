<?php
/**
 * 主控端 API - 负责连接前端与各个节点
 * 修改记录：新增 Iperf3 后端频率限制
 */
error_reporting(0);
header('Content-Type: application/json; charset=utf-8');

// 加载配置
$config = require 'config.php';
$action = $_POST['action'] ?? '';

// === 获取 Turnstile 配置 ===
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
        
        if (empty($token)) {
            echo json_encode(['status' => 'error', 'message' => 'Security check failed: CAPTCHA missing.']);
            exit;
        }

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
        
        if (!$cf_json || !($cf_json['success'] ?? false)) {
            echo json_encode(['status' => 'error', 'message' => 'Security check failed. Please refresh the page.']);
            exit;
        }
    }
    // >>>>>>>>>> Cloudflare Turnstile 验证逻辑结束 <<<<<<<<<<

    // >>>>>>>>>> 新增：Iperf3 后端频率限制 (防绕过) 开始 <<<<<<<<<<
    $tool = $_POST['tool'] ?? '';
    if ($tool === 'iperf3') {
        // 1. 获取客户端真实 IP
        $clientIp = $_SERVER['HTTP_CF_CONNECTING_IP'] ?? $_SERVER['REMOTE_ADDR'];
        
        // 2. 配置限制 (每小时 2 次)
        $limit = 2; 
        $hour = date('YmdH'); // 精确到小时，如 2023102712
        $tmpDir = sys_get_temp_dir();
        // 生成唯一的临时文件路径
        $limitFile = $tmpDir . '/lg_iperf_' . $hour . '_' . md5($clientIp);
        
        // 3. 读取当前次数
        $currentCount = 0;
        if (file_exists($limitFile)) {
            $currentCount = (int)file_get_contents($limitFile);
        }
        
        // 4. 判断是否超限
        if ($currentCount >= $limit) {
            echo json_encode([
                'status' => 'error', 
                'message' => "Hourly limit reached ($limit/hour). Please try again later."
            ]);
            exit; // 直接终止，不请求节点
        }
        
        // 5. 计数 +1
        file_put_contents($limitFile, $currentCount + 1);
    }
    // >>>>>>>>>> 新增：Iperf3 后端频率限制 结束 <<<<<<<<<<

    $node_id = $_POST['node_id'] ?? '';
    
    if (!isset($config['nodes'][$node_id])) {
        echo json_encode(['status' => 'error', 'message' => 'Node not found']);
        exit;
    }
    $node = $config['nodes'][$node_id];
    
    $postData = $_POST;
    $postData['key'] = $node['key'];
    
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
