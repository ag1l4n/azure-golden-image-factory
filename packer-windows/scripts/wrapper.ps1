# wrapper.ps1 — runs as SYSTEM via scheduled task, fully isolated from WinRM

$username = (Get-Content 'C:\Windows\Temp\u.txt' -Raw -ErrorAction SilentlyContinue).Trim()
$password = (Get-Content 'C:\Windows\Temp\p.txt' -Raw -ErrorAction SilentlyContinue).Trim()

$cisScript = 'C:\Windows\Temp\cis-harden.ps1'

# Pre-set variables the CIS script expects
$NewLocalAdmin         = $username
$NewLocalAdminPassword = ConvertTo-SecureString $password -AsPlainText -Force

# Suppress interactive prompts
function global:Read-Host {
    param([string]$Prompt, [switch]$AsSecureString)
    Write-Host "Read-Host suppressed: $Prompt"
    if ($AsSecureString) {
        return (ConvertTo-SecureString $password -AsPlainText -Force)
    }
    return $password
}

# Suppress reboot — Packer windows-restart provisioner handles this
function global:Restart-Computer {
    param([switch]$Force, [int]$Delay)
    Write-Host 'Restart-Computer suppressed - Packer handles reboot.'
}

function global:Stop-Computer {
    param([switch]$Force)
    Write-Host 'Stop-Computer suppressed.'
}

try {
    . $cisScript
    Write-Host 'CIS hardening completed successfully.'
    'done' | Out-File 'C:\Windows\Temp\done.txt' -Encoding UTF8
} catch {
    Write-Host "ERROR: $_"
    $_ | Out-File 'C:\Windows\Temp\failed.txt' -Encoding UTF8
    'done' | Out-File 'C:\Windows\Temp\done.txt' -Encoding UTF8  # still signal completion so polling exits
} finally {
    Remove-Item $cisScript -Force -ErrorAction SilentlyContinue
}

exit 0
