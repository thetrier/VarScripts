# romulus.dobrin@temenos.com
# Version: 1.1 (FIXED)
# Windows Incident Response Gathering Script

function Test-Admin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Wait-ForKeyPress {
    Write-Host ""
    Write-Host "Please press ENTER to continue or ESC to exit the script..." -ForegroundColor Cyan

    while ($true) {
        try {
            $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        catch {
            Write-Host "Non-interactive console detected. Auto-continuing..." -ForegroundColor Yellow
            return
        }

        switch ($key.VirtualKeyCode) {
            13 { return }
            27 { Write-Host "Exiting script..." -ForegroundColor Yellow; exit }
        }
    }
}

# --- Admin check ---
if (-not (Test-Admin)) {

    Write-Host "Not running as Administrator. Requesting elevation..." -ForegroundColor Yellow

    $exe = if ($PSVersionTable.PSEdition -eq "Core") { "pwsh.exe" } else { "powershell.exe" }

    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""

    Start-Process $exe -Verb RunAs -ArgumentList $arguments

    Write-Host "You are not running with admin privileges." -ForegroundColor Red

    Wait-ForKeyPress
    return
}

# --- Header ---
Write-Host "Windows IR Collection Tool" -ForegroundColor Cyan
Write-Host ""

Wait-ForKeyPress

$Hostname = $env:COMPUTERNAME

# ALWAYS use script location
$Folder = Join-Path $PSScriptRoot $Hostname

if (!(Test-Path $Folder)) {
    New-Item -ItemType Directory -Path $Folder | Out-Null
}

$ResultsFile = Join-Path $Folder "${Hostname}_results.txt"

# reset file safely
"" | Set-Content -Path $ResultsFile

# --- FIXED LOGGING SYSTEM ---
function Write-Log {
    param([string]$Text)
    Add-Content -Path $ResultsFile -Value $Text -Encoding UTF8
}

function Run-Command {
    param(
        [string]$CommandName,
        [scriptblock]$Command
    )

    try {
        $output = & $Command
        $output | Out-File -Append -FilePath $ResultsFile -Encoding UTF8
    }
    catch {
        Write-Log "Command $CommandName failed: $_"
    }
}

function Write-Section {
    param([string]$Title)
    Write-Log ""
    Write-Log "==================== $Title ===================="
    Write-Log ""
}

# --- PROGRESS ---
$TotalSections = 22
$CurrentSection = 0

function Show-ProgressBar {
    $script:CurrentSection++
    $Percent = [int](($CurrentSection / $TotalSections) * 100)

    Write-Progress -Activity "Windows IR Collection" `
        -Status "$Percent% Complete" `
        -PercentComplete $Percent
}

# =========================
# SYSTEM INFO
# =========================
Write-Section "Windows System Information"

Run-Command "SystemInfo" { systeminfo }
Run-Command "OS Info" { Get-ComputerInfo }

Show-ProgressBar

# =========================
# PROCESSES
# =========================
Write-Section "Processes Running"

Run-Command "Processes" {

    $Processes = Get-CimInstance Win32_Process |
        Group-Object ProcessId -AsHashTable

    Get-Process |
        ForEach-Object {

            $p = $Processes[[string]$_.Id]

            [PSCustomObject]@{
                ProcessName = $_.ProcessName
                PID         = $_.Id
                ParentPID   = $_.Parent.Id
                StartTime   = $_.StartTime
                CPU         = $_.CPU
                CommandLine = $p.CommandLine
            }
        } |
        Sort-Object ProcessName
}

Show-ProgressBar

# =========================
# NETWORK
# =========================
Write-Section "Network Connections"

Run-Command "NetTCPConnection" {

    Get-NetTCPConnection |
        Select-Object `
            LocalAddress,
            LocalPort,
            RemoteAddress,
            RemotePort,
            State,
            @{Name='PID';Expression={$_.OwningProcess}},
            @{Name='CommandLine';Expression={
                (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.OwningProcess)" -ErrorAction SilentlyContinue).CommandLine
            }} |
        Sort-Object PID
}

Run-Command "NetUDPEndpoint" {

    $Processes = Get-CimInstance Win32_Process |
        Group-Object ProcessId -AsHashTable

    Get-NetUDPEndpoint |
        Select-Object `
            LocalAddress,
            LocalPort,
            @{Name='PID';Expression={$_.OwningProcess}},
            @{Name='CommandLine';Expression={
                $Processes[[string]$_.OwningProcess].CommandLine
            }} |
        Sort-Object PID
}

Show-ProgressBar

# =========================
# SERVICES
# =========================
Write-Section "Services"

Run-Command "Services Inventory" {
    Get-CimInstance Win32_Service |
        Select-Object Name, DisplayName, State, StartMode, PathName |
        Sort-Object State
}

Show-ProgressBar

# =========================
# LOCAL USERS
# =========================
Write-Section "Local Users"

Run-Command "Local Users" {

    Get-LocalUser |
        Select-Object Name, Enabled, Description, LastLogon,
        PasswordLastSet, PasswordExpires, PasswordRequired
}

Show-ProgressBar

# =========================
# ADMIN GROUP
# =========================
Write-Section "Local Administrators"

Run-Command "Administrators Group" {
    Get-LocalGroupMember -Group "Administrators"
}

Show-ProgressBar

# =========================
# SCRIPTS
# =========================
Write-Section "Scripts Created"

Run-Command "Scripts created" {

    $Paths = @(
        $env:USERPROFILE,
        "C:\Users",
        "C:\ProgramData"
    )

    $Extensions = @(
        ".ps1",".psm1",".psd1",
        ".bat",".cmd",".com",
        ".vbs",".vbe",".js",".jse",
        ".wsf",".wsh"
    )

    $Results = Get-ChildItem -Path $Paths -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Extension -in $Extensions -and
            $_.CreationTime -ge (Get-Date).AddDays(-30)
        } |
        Select-Object FullName, Extension, CreationTime, LastWriteTime, Length |
        Sort-Object CreationTime -Descending

    if ($Results.Count -gt 0) {
        Write-Log "Scripts found: $($Results.Count)"
        $Results
    }
    else {
        Write-Log "No scripts found in last 30 days"
    }
}

Show-ProgressBar

# =========================
# LOG FINAL
# =========================
Write-Log ""
Write-Log "==================== EXECUTION SUMMARY ===================="
Write-Log "Collection complete"
Write-Log "User      : $env:USERNAME"
Write-Log "Hostname  : $Hostname"
Write-Log "Date/Time : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Log "Script    : $PSCommandPath"
Write-Log "==========================================================="

Write-Host "DONE" -ForegroundColor Green
Write-Host "Results: $ResultsFile" -ForegroundColor Cyan
Pause
Read-Host "Press Enter to exit"