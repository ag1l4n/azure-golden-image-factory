# wrapper.ps1 — runs as SYSTEM via scheduled task

$username = (Get-Content 'C:\Windows\Temp\u.txt' -Raw -ErrorAction SilentlyContinue).Trim()
$password = (Get-Content 'C:\Windows\Temp\p.txt' -Raw -ErrorAction SilentlyContinue).Trim()

$cisScript = 'C:\Windows\Temp\cis-harden.ps1'

$NewLocalAdmin         = $username
$NewLocalAdminPassword = ConvertTo-SecureString $password -AsPlainText -Force

# Block OS-level reboots so the CIS script cannot restart the VM
# Packer's windows-restart provisioner handles the reboot cleanly after this task completes
$wuPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
if (-not (Test-Path $wuPath)) { New-Item -Path $wuPath -Force | Out-Null }
Set-ItemProperty -Path $wuPath -Name 'NoAutoRebootWithLoggedOnUsers' -Value 1 -Type DWord -Force

# Also disable shutdown/restart via shutdown.exe for the duration of this script
# This catches any direct shutdown.exe calls the script might make
$null = & shutdown /a 2>$null  # abort any pending shutdown

function global:Read-Host {
    param([string]$Prompt, [switch]$AsSecureString)
    Write-Host "Read-Host suppressed: $Prompt"
    if ($AsSecureString) {
        return (ConvertTo-SecureString $password -AsPlainText -Force)
    }
    return $password
}

function global:Restart-Computer {
    param([switch]$Force, [int]$Delay)
    Write-Host 'Restart-Computer suppressed - Packer handles reboot.'
}

function global:Stop-Computer {
    param([switch]$Force)
    Write-Host 'Stop-Computer suppressed.'
}

# Also intercept shutdown.exe calls via a wrapper function
function global:shutdown {
    Write-Host 'shutdown.exe suppressed by wrapper.'
}

try {
    . $cisScript
    Write-Host 'CIS hardening completed successfully.'
    'done' | Out-File 'C:\Windows\Temp\done.txt' -Encoding UTF8
} catch {
    Write-Host "ERROR: $_"
    $_ | Out-File 'C:\Windows\Temp\failed.txt' -Encoding UTF8
    'done' | Out-File 'C:\Windows\Temp\done.txt' -Encoding UTF8
} finally {
    # Restore reboot policy
    Remove-ItemProperty -Path $wuPath -Name 'NoAutoRebootWithLoggedOnUsers' -ErrorAction SilentlyContinue
    Remove-Item $cisScript -Force -ErrorAction SilentlyContinue
}

exit 0
