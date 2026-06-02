
# Basic port scanner in powershell
# Ver 0.2 - perhaps will improve in time
# Author : The Trier
# Contact - well, this one is hard :)
# Modified the way is connecting due to powershell modifications in handling functions
# BE WARNED THAT PORT SCANNING OF EXTERNAL IPs CAN BRING LEGAL PROBLEMS!!! SO PLEASE USE THIS WITH CAUTION.

#define ip

$ip = Read-host @("Insert IP addresses separated by space")
$ports = Read-Host @("Insert ports separated by space")

foreach ($ips in $ip) {
    foreach ($port in $ports) {
    $connection = New-Object System.Net.Sockets.TcpClient($ipaddress, $port)
    }
}
if ($connection.Connected) {
    Write-Host "$ips has $port opened"
}
else {
    Write-Host "Port $port closed"
}
