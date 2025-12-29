<?php
// ==========================================
// 节点配置变量 (默认留空，等待配置)
// ==========================================
$node_name    = '';
$node_country = '';
$node_ipv4    = '';
$node_ipv6    = '';
$agent_url    = '';
$agent_key    = '';

return [
    // === 新增：节点自动注册令牌 ===
    // 在安装脚本中设置此值，Agent 上报时需携带此 Token 才能注册成功
    'node_registration_token' => '', 

    'nodes' => [
        1 => [
            'name'     => $node_name,
            'country'  => $node_country,
            'ipv4'     => $node_ipv4,
            'ipv6'     => $node_ipv6,
            'api_url'  => $agent_url,
            'key'      => $agent_key,
            'unlock'   => []
        ]
    ]
];
