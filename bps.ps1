
# Basic port scanner in powershell
# Ver 0.1 - perhaps will improve in time
# Author : The Trier
# Contact - well, this one is hard :)

$ips = Read-host @("Insert IP addresses separated by space")
$ports = Read-Host @("Insert ports separated by space")

foreach ($ip in $ips) {
    foreach ($port in $ports) {
    $connection = New-Object System.Net.Sockets.TcpClient($ipaddress, $port)
    }
}
if ($connection.Connected) {
    Write-Host "$ip has $port opened"
}
else {
    Write-Host "$ip has port $port closed"
}
