<?php
/**
 * 最终版 Agent - 支持双栈检测 & Iperf3 自动切换
 */
error_reporting(0);
header('Content-Type: text/plain; charset=utf-8');
header('Access-Control-Allow-Origin: *');

// ==========================================
// 配置变量 (安装脚本会自动替换此处)
// ==========================================
$SECRET_KEY   = ''; 
$PUBLIC_IP_V4 = ''; 
$PUBLIC_IP_V6 = ''; 
// ==========================================

if (($_POST['key'] ?? '') !== $SECRET_KEY) {
    http_response_code(403);
    exit("Auth Failed");
}

$action = $_POST['action'] ?? '';
$tool   = $_POST['tool'] ?? '';
$target = $_POST['target'] ?? '';
$proto  = $_POST['proto'] ?? 'IPv4';

// 命令查找函数
function get_cmd($names) {
    $list = is_array($names) ? $names : [$names];
    $paths = ['/usr/bin/', '/bin/', '/usr/sbin/', '/sbin/'];
    foreach ($list as $name) {
        foreach ($paths as $path) {
            if (@file_exists($path . $name)) {
                return $path . $name;
            }
        }
    }
    return $list[0]; 
}

// === 获取流媒体结果 (读取合并后的 JSON) ===
if ($action === 'get_unlock') {
    $file = __DIR__ . '/unlock_result.json';
    
    if (file_exists($file)) {
        // 直接输出文件内容
        echo file_get_contents($file);
    } else {
        // 如果文件不存在，返回空结构
        echo json_encode([
            'v4' => null,
            'v6' => null
        ]);
    }
    exit;
}

if ($action === 'run_tool') {

    // === Iperf3 ===
    if ($tool === 'iperf3') {
        $port = rand(30000, 31000);
        
        // 杀掉旧进程
        exec("pkill -u www-data iperf3 > /dev/null 2>&1");
        exec("pkill -u www iperf3 > /dev/null 2>&1");
        
        // 启动服务器 (同时监听 v4 和 v6)
        $bin = get_cmd('iperf3');
        // -1: 接受一次连接后退出, -D: 后台运行
        exec("$bin -s -p $port -1 -D > /dev/null 2>&1");
        
        // 等待启动
        usleep(300000); 
        
        // 根据请求协议返回对应的 IP
        $server_ip = ($proto === 'IPv6') ? $PUBLIC_IP_V6 : $PUBLIC_IP_V4;
        
        // 如果没有配置对应的 IP，回退到另一个 (防止报错)
        if (empty($server_ip)) {
            $server_ip = empty($PUBLIC_IP_V4) ? $PUBLIC_IP_V6 : $PUBLIC_IP_V4;
        }

        echo "iperf3 -c $server_ip -p $port";
        exit;
    }

    // === Ping / MTR / Traceroute ===
    if (!preg_match('/^[a-zA-Z0-9\.\-\:]+$/', $target)) {
        exit("Error: Invalid target.");
    }

    if (!function_exists('popen')) {
        exit("Error: 'popen' function is disabled. Please enable it in php.ini");
    }

    $flag = ($proto === 'IPv6') ? '-6' : '-4';
    $target = escapeshellarg($target);
    $cmd = '';

    if ($tool === 'ping') {
        $bin = get_cmd('ping'); 
        $cmd = "$bin $flag -c 4 -w 10 $target";
    } elseif ($tool === 'mtr') {
        $bin = get_cmd('mtr');
        $cmd = "$bin $flag -r -c 10 -n $target";
    } else {
        $bin = get_cmd(['traceroute', 'tracepath']);
        $cmd = "$bin $flag -w 2 -q 1 -n $target";
    }

    // 执行并输出
    $handle = popen("$cmd 2>&1", 'r');
    if (is_resource($handle)) {
        while (!feof($handle)) {
            $line = fgets($handle);
            echo $line;
            @flush();
        }
        pclose($handle);
    } else {
        echo "Error: Failed to launch command: $cmd";
    }
    exit;
}

echo "Agent Ready";
?>
