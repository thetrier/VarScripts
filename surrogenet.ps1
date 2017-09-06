$ipaddress = read-host "Please give me one ip"
$port = read-host "Please give me one port"

$connection = New-Object System.Net.Sockets.TcpClient($ipaddress, $port)


echo "Connecting .........."

if ($connection.Connected) {
    Write-Host "Connected"
}
else {
    Write-Host "Failed"
}