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
