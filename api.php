<?php
/**
 * 主控端 API - 负责连接前端与各个节点
 * 修改记录：移除 run_tool 的 Turnstile 验证 (前端 JS 控制下载时验证)
 */
error_reporting(0);
header('Content-Type: application/json; charset=utf-8');

// 加载配置
$configFile = 'config.php';
$config = require $configFile;
$action = $_POST['action'] ?? '';

// === 获取 Turnstile 配置 ===
// 注意：虽然这里获取了配置，但在 run_tool 中不再强制检查，
// 这样 Ping/MTR 可以直接通行，而下载测试的验证由前端 index.php 负责弹窗拦截。
$enableTurnstile = $config['enable_turnstile'] ?? true;
$cfSecretKey     = $config['cf_secret_key'] ?? '';

// >>>>>>>>>> 新增：节点自动注册接口 开始 <<<<<<<<<<
if ($action === 'add_node') {
    $regToken = $config['node_registration_token'] ?? '';
    $sentToken = $_POST['reg_token'] ?? '';
    
    // 1. 安全校验：Token 必须存在且匹配
    if (empty($regToken) || $sentToken !== $regToken) {
        echo json_encode(['status' => 'error', 'message' => 'Invalid Registration Token']);
        exit;
    }

    // 2. 接收参数
    $newNode = [
        'name'    => $_POST['name'] ?? 'New Node',
        'country' => $_POST['country'] ?? 'UN',
        'ipv4'    => $_POST['ipv4'] ?? '',
        'ipv6'    => $_POST['ipv6'] ?? '',
        'api_url' => $_POST['api_url'] ?? '',
        'key'     => $_POST['key'] ?? '',
        'unlock'  => [] // 初始化为空数组
    ];

    // 3. 写入配置文件
    // 注意：config.php 需要有写入权限 (chmod 666)
    $config['nodes'][] = $newNode;
    
    // 使用 var_export 重新生成 PHP 文件内容
    $content = "<?php\n" .
               "// ==========================================\n" .
               "// Auto-generated config file\n" .
               "// ==========================================\n" .
               "return " . var_export($config, true) . ";\n";
    
    if (file_put_contents($configFile, $content)) {
        echo json_encode(['status' => 'success', 'message' => 'Node added successfully']);
    } else {
        echo json_encode(['status' => 'error', 'message' => 'Failed to write config.php (Check Permissions)']);
    }
    exit;
}
// >>>>>>>>>> 新增：节点自动注册接口 结束 <<<<<<<<<<


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
    
    // >>>>>>>>>> [已移除] Cloudflare Turnstile 验证逻辑 <<<<<<<<<<
    // 原有的验证逻辑已被删除，以允许 Ping/MTR 无需验证码直接运行。
    // 下载文件的验证逻辑完全由前端 (index.php) 的 JavaScript 控制。

    // >>>>>>>>>> 新增：Iperf3 后端频率限制 (防绕过) 开始 <<<<<<<<<<
    $tool = $_POST['tool'] ?? '';
    if ($tool === 'iperf3') {
        // 1. 获取客户端真实 IP (适配 Cloudflare CDN)
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
    
    // 清理掉不需要转发给 Agent 的参数
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
