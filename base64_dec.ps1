# Script for decoding base64 strings for Windows (for Linux is easy-peasy :] )
# Ver 0.1 - i might add other types of decoding
# Author : The Trier
# Contact - well, this one is hard :)

echo "A base64 string will end, in majority of cases with one '=' sign or two '==' signs `n"
echo "This script is to decode UTF8 characters encoded base64 `n"
echo "Keep in mind, when you copy-paste a base64 string from notepad or CMD, windows use CR/LF at the end of a line!!!"
echo "So you will need to go LINE BY LINE copy and paste base64 string."
echo "This does not apply though to powershell ISE"

$str64 = Read-Host "Please insert (copy/paste) the base64 string (EQ: QmFzZTY0IHN0cmluZwo=)"
$dec = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($str64)) 2>$null
echo "Decoded string is:`n"
echo $dec
exit

