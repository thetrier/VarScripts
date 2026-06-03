# th3tri3r
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
$TotalSections = 21
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

Run-Command "Services Inventory (CIM)" {
    Get-CimInstance Win32_Service |
        Select-Object Name, DisplayName, State, StartMode, PathName |
        Sort-Object State
}

Show-ProgressBar

Write-Section "Services Modified in Last 30 Days (Registry)"

Run-Command "Recently Modified Service Keys" {

    Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services" |
    Where-Object {
        $_.LastWriteTime -gt (Get-Date).AddDays(-30)
    } |
    Select-Object PSChildName, LastWriteTime |
    Sort-Object LastWriteTime -Descending
}

Show-ProgressBar

Write-Section "Scheduled Tasks"

Run-Command "Scheduled Tasks Full IR Enrichment" {

    Get-ScheduledTask | ForEach-Object {

        $task = $_
        $info = Get-ScheduledTaskInfo -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue

        try {
            $xml = Export-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction Stop
            [xml]$t = $xml

            $actions = $t.Task.Actions.Exec | Where-Object { $_ -ne $null -and $_.Command -ne "" }

            foreach ($action in $actions) {

                $cmd = "$($action.Command) $($action.Arguments)".Trim()
                $exe = $action.Command -replace '"',''

                $file = if ($exe -and (Test-Path $exe)) {
                    Get-Item $exe -ErrorAction SilentlyContinue
                } else {
                    $null
                }

                [PSCustomObject]@{
                    TaskName      = $task.TaskName
                    TaskPath      = $task.TaskPath
                    State         = $task.State
                    CommandLine   = $cmd
                    BinaryPath    = $exe
                    CreationTime  = $file.CreationTime
                    LastWriteTime = $file.LastWriteTime
                    LastRunTime   = $info.LastRunTime
                    NextRunTime   = $info.NextRunTime
                }
            }
        }
        catch {
            Write-Output "Failed parsing task: $($task.TaskName)"
        }
    }
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


#=================================
#LOGON SESSIONS
#=================================

Write-Section "Logon Sessions"

Run-Command "Logon Sessions" {
    quser
}

Run-Command "Logged On Users" {
    query user
}

Show-ProgressBar

#==========================
# FAILED LOGONS
#==========================
Write-Section "Failed Logons"

Run-Command "Failed Logons" {

    Get-WinEvent -FilterHashtable @{
        LogName='Security'
        Id=4625
    } -MaxEvents 100
}

Show-ProgressBar

# ============================
# Executables modified/written
# ============================
Write-Section "Executables Modified Last 30 Days"

Run-Command "Modified Executables" {

    Get-ChildItem C:\ -Recurse -Include *.exe `
        -ErrorAction SilentlyContinue |
        Where-Object {
            $_.LastWriteTime -gt (Get-Date).AddDays(-30)
        } |
        Select-Object FullName, LastWriteTime
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

#============================
# PERSISTENCE STARTUP COMMANDS
#============================
Write-Section "Startup Items"

Run-Command "Startup Commands" {

    Get-CimInstance Win32_StartupCommand |
    Select-Object Name, Command, Location, User
}

Show-ProgressBar

#===========================
#PERSISTENCE - REGISTRY
#===========================

Write-Section "Autoruns Registry Locations"

Run-Command "Run Keys" {

    $RunLocations = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
    )

    foreach ($Location in $RunLocations) {

        if (Test-Path $Location) {

            Write-Output "`n===== $Location ====="

            Get-ItemProperty $Location
        }
    }
}

#=============================
#PERSISTENCE - STARTUP FOLDER
#=============================

Run-Command "Startup Folder Items" {

    Get-ChildItem `
        "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup" `
        -ErrorAction SilentlyContinue

    Get-ChildItem `
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup" `
        -ErrorAction SilentlyContinue
}

Show-ProgressBar

#==========================
#PERSISTENCE WMI
#==========================

Write-Section "WMI Persistence Checks"

Run-Command "WMI Event Filters" {

    Get-WmiObject -Namespace root\subscription `
        -Class __EventFilter
}

Run-Command "WMI Event Consumers" {

    Get-WmiObject -Namespace root\subscription `
        -Class CommandLineEventConsumer
}

Run-Command "WMI Filter Bindings" {

    Get-WmiObject -Namespace root\subscription `
        -Class __FilterToConsumerBinding
}

Show-ProgressBar

# =========================
# CMD - RECENT COMMANDS
# =========================

Write-Section "Recent Commands"

Run-Command "DOSKEY History" {
    doskey /history
}

# =========================
# POWERSHELL HISTORY
# =========================

Write-Section "PowerShell History"

$Users = Get-ChildItem C:\Users -Directory -ErrorAction SilentlyContinue

foreach ($User in $Users) {

    $HistoryPath = Join-Path $User.FullName `
        "AppData\Roaming\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt"

    if (Test-Path $HistoryPath) {

        Add-Content $ResultsFile "===== PowerShell History for $($User.Name) ====="

        Get-Content $HistoryPath |
            Out-File -Append $ResultsFile

        Add-Content $ResultsFile ""
    }
}

Show-ProgressBar

# =========================
# SOFTWARE INVENTORY
# =========================

Write-Section "Installed Software Inventory"

Run-Command "Installed Software" {

    Get-ItemProperty `
        HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* ,
        HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate |
        Sort-Object DisplayName
}

Show-ProgressBar

# =========================
# USB HISTORY
# =========================

Write-Section "USB Device History"

Run-Command "USB Storage Devices" {

    Get-ItemProperty `
        HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR\*\* `
        -ErrorAction SilentlyContinue
}

# =========================
# MOUNTED DEVICES
# =========================

Run-Command "Mounted Devices" {

    Get-ItemProperty `
        HKLM:\SYSTEM\MountedDevices
}

Show-ProgressBar

# =========================
# RDP HISTORY
# =========================

Write-Section "RDP History"

Run-Command "RDP Client Connections" {

    Get-ItemProperty `
        "HKCU:\Software\Microsoft\Terminal Server Client\Servers\*" `
        -ErrorAction SilentlyContinue
}

Run-Command "RDP Recent Servers" {

    Get-ItemProperty `
        "HKCU:\Software\Microsoft\Terminal Server Client\Default" `
        -ErrorAction SilentlyContinue
}

Run-Command "Remote Desktop Event Logs" {

    Get-WinEvent -LogName `
        "Microsoft-Windows-TerminalServices-LocalSessionManager/Operational" `
        -MaxEvents 100
}

Show-ProgressBar

# =========================
# BROWSER ARTIFACTS
# =========================

Write-Section "Browser Artifacts"

$Users = Get-ChildItem C:\Users -Directory -ErrorAction SilentlyContinue

foreach ($User in $Users) {

    Add-Content $ResultsFile "`n===== Browser Artifacts for $($User.Name) ====="

    $ChromeHistory = Join-Path `
        $User.FullName `
        "AppData\Local\Google\Chrome\User Data\Default\History"

    if (Test-Path $ChromeHistory) {

        Add-Content $ResultsFile "[+] Chrome History File Found:"
        Add-Content $ResultsFile $ChromeHistory

        Copy-Item `
            $ChromeHistory `
            -Destination $Folder `
            -ErrorAction SilentlyContinue
    }

    $EdgeHistory = Join-Path `
        $User.FullName `
        "AppData\Local\Microsoft\Edge\User Data\Default\History"

    if (Test-Path $EdgeHistory) {

        Add-Content $ResultsFile "[+] Edge History File Found:"
        Add-Content $ResultsFile $EdgeHistory

        Copy-Item `
            $EdgeHistory `
            -Destination $Folder `
            -ErrorAction SilentlyContinue
    }

    $FirefoxProfiles = Join-Path `
        $User.FullName `
        "AppData\Roaming\Mozilla\Firefox\Profiles"

    if (Test-Path $FirefoxProfiles) {

        Add-Content $ResultsFile "[+] Firefox Profiles Found:"
        Add-Content $ResultsFile $FirefoxProfiles

        Get-ChildItem `
            $FirefoxProfiles `
            -Directory `
            -ErrorAction SilentlyContinue |
            ForEach-Object {

                $PlacesFile = Join-Path $_.FullName "places.sqlite"

                if (Test-Path $PlacesFile) {

                    Copy-Item `
                        $PlacesFile `
                        -Destination $Folder `
                        -ErrorAction SilentlyContinue
                }
            }
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
