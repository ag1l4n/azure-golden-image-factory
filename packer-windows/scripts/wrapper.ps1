# wrapper.ps1 — runs as SYSTEM via scheduled task, isolated from WinRM

$username = Get-Content 'C:\Windows\Temp\cis-username.txt' -Raw
$password = Get-Content 'C:\Windows\Temp\cis-password.txt' -Raw

$cisScript = 'C:\Windows\Temp\cis-harden.ps1'

$NewLocalAdmin         = $username.Trim()
$NewLocalAdminPassword = ConvertTo-SecureString $password.Trim() -AsPlainText -Force

function global:Read-Host {
    param(
        [string]$Prompt,
        [switch]$AsSecureString
    )
    Write-Host "Read-Host suppressed: $Prompt"
    if ($AsSecureString) {
        return (ConvertTo-SecureString $password.Trim() -AsPlainText -Force)
    }
    return $password.Trim()
}

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
    'done' | Out-File 'C:\Windows\Temp\cis-complete.txt' -Encoding UTF8
} catch {
    Write-Host "ERROR: $_"
    $_ | Out-File 'C:\Windows\Temp\cis-failed.txt' -Encoding UTF8
} finally {
    Remove-Item $cisScript -Force -ErrorAction SilentlyContinue
}
