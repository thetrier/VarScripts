# TCP port verifying
#Due to new powershell interpretation of functions i've added some modifications

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
