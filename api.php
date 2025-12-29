<?php
/**
 * 主控端 API - 负责连接前端与各个节点
 */
error_reporting(0);
header('Content-Type: application/json; charset=utf-8');
// 加载配置
$config = require 'config.php';
$action = $_POST['action'] ?? '';
// === 1. 获取节点列表 (并抓取流媒体状态) ===
if ($action === 'get_nodes') {
    $nodes = $config['nodes'];
    $final_nodes = [];
    // 并发处理：如果节点多，这里可以用 curl_multi 优化，
    // 但为了代码稳定性，这里先用简单的遍历（少量节点没影响）。
    foreach ($nodes as $id => $node) {
        // 默认流媒体状态（全空）
        $unlock_data = [
            'v4' => null,
            'v6' => null
        ];
        // 构造请求去问节点的 agent.php
        $postData = [
            'key'    => $node['key'],
            'action' => 'get_unlock'
        ];
        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, $node['api_url']);
        curl_setopt($ch, CURLOPT_POST, 1);
        curl_setopt($ch, CURLOPT_POSTFIELDS, http_build_query($postData));
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        
        // 超时设置：非常重要！
        // 设置为 2 秒，防止某个节点挂了导致整个网页卡住
        curl_setopt($ch, CURLOPT_TIMEOUT, 2); 
        curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 2);
        
        // 忽略 SSL 证书错误 (如果是 https 节点)
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, false);
        
        $response = curl_exec($ch);
        $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
        // 如果请求成功，解析 JSON
        if ($http_code == 200 && $response) {
            $json = json_decode($response, true);
            if (is_array($json)) {
                $unlock_data = $json;
            }
        }
        // 把抓取到的流媒体数据，塞进节点信息里
        $node['unlock'] = $unlock_data;
        
        // 安全起见，删除 API Key，不发给前端
        unset($node['key']);
        unset($node['api_url']);
        
        $final_nodes[$id] = $node;
    }
    echo json_encode(['status' => 'success', 'data' => $final_nodes]);
    exit;
}
// === 2. 运行工具 (Ping/MTR/Iperf3) ===
if ($action === 'run_tool') {
    $node_id = $_POST['node_id'] ?? '';
    
    if (!isset($config['nodes'][$node_id])) {
        echo json_encode(['status' => 'error', 'message' => 'Node not found']);
        exit;
    }
    $node = $config['nodes'][$node_id];
    
    // 透传所有参数给 Agent
    $postData = $_POST;
    $postData['key'] = $node['key']; // 加上密钥
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $node['api_url']);
    curl_setopt($ch, CURLOPT_POST, 1);
    curl_setopt($ch, CURLOPT_POSTFIELDS, http_build_query($postData));
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    // 工具运行时间较长，给 30-60 秒超时
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
