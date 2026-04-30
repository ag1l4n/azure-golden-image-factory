# wrapper.ps1 — runs as SYSTEM via scheduled task

$username = (Get-Content 'C:\Windows\Temp\u.txt' -Raw -ErrorAction SilentlyContinue).Trim()
$password = (Get-Content 'C:\Windows\Temp\p.txt' -Raw -ErrorAction SilentlyContinue).Trim()

$cisScript = 'C:\Windows\Temp\cis-harden.ps1'

$NewLocalAdmin         = $username
$NewLocalAdminPassword = ConvertTo-SecureString $password -AsPlainText -Force

# Block OS-level reboots during hardening
$wuPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
if (-not (Test-Path $wuPath)) { New-Item -Path $wuPath -Force | Out-Null }
Set-ItemProperty -Path $wuPath -Name 'NoAutoRebootWithLoggedOnUsers' -Value 1 -Type DWord -Force
$null = & shutdown /a 2>$null

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

function global:shutdown {
    Write-Host 'shutdown.exe suppressed by wrapper.'
}

try {
    . $cisScript
    Write-Host 'CIS hardening completed successfully.'
} catch {
    Write-Host "ERROR: $_"
    $_ | Out-File 'C:\Windows\Temp\failed.txt' -Encoding UTF8
} finally {
    Remove-ItemProperty -Path $wuPath -Name 'NoAutoRebootWithLoggedOnUsers' -ErrorAction SilentlyContinue
    Remove-Item $cisScript -Force -ErrorAction SilentlyContinue
}

# --- RESTORE WINRM SO PACKER CAN RECONNECT AFTER RESTART ---
# Must run BEFORE done.txt is written so Packer doesn't try to reconnect too early
Write-Host 'Restoring WinRM for Packer post-hardening...'

# Remove GPO policy keys that disable Basic auth
$paths = @(
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Client',
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service'
)
foreach ($path in $paths) {
    if (Test-Path $path) {
        Remove-ItemProperty -Path $path -Name 'AllowBasic'               -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $path -Name 'AllowUnencryptedTraffic'  -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $path -Name 'AllowDigest'              -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $path -Name 'DisableRunAs'             -ErrorAction SilentlyContinue
        Write-Host "Cleared WinRM policy overrides at: $path"
    }
}

# Remove LocalAccountTokenFilterPolicy restriction
Set-ItemProperty `
    -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' `
    -Name 'LocalAccountTokenFilterPolicy' `
    -Value 1 -Type DWord -Force

# Restore WSMan Basic auth
Set-Item 'WSMan:\localhost\Service\Auth\Basic' $true -ErrorAction SilentlyContinue
Set-Item 'WSMan:\localhost\Client\Auth\Basic'  $true -ErrorAction SilentlyContinue

# Re-open port 5986 in firewall
netsh advfirewall firewall add rule `
    name='Packer-WinRM-HTTPS' `
    dir=in action=allow protocol=TCP localport=5986 | Out-Null

# Restart WinRM to apply — safe here because this runs in a scheduled task,
# NOT in the WinRM session itself, so restarting it doesn't drop any connection
Restart-Service WinRM -Force
Write-Host 'WinRM restored successfully.'
# --- END RESTORE ---

# Signal completion AFTER WinRM is restored
'done' | Out-File 'C:\Windows\Temp\done.txt' -Encoding UTF8

exit 0
