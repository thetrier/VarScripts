
# Basic port scanner in powershell
# Ver 0.2 - perhaps will improve in time
# Author : The Trier
# Contact - well, this one is hard :)
# Modified the way is connecting due to powershell modifications in handling functions
# BE WARNED THAT PORT SCANNING OF EXTERNAL IPs CAN BRING LEGAL PROBLEMS!!! SO PLEASE USE THIS WITH CAUTION.

#define ip

$ipaddress = Read-Host "Please give me one IP"
$port = Read-Host "Please give me one port"

Write-Host "Connecting .........."

try {
    $connection = New-Object System.Net.Sockets.TcpClient
    $connection.Connect($ipaddress, [int]$port)

    if ($connection.Connected) {
        Write-Host "Connected"
    }
}
catch {
    Write-Host "Failed to connect to ${ipaddress}:${port}" -ForegroundColor Red
}
finally {
    if ($connection) {
        $connection.Close()
    }
}
