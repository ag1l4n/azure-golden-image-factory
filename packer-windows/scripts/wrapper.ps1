# wrapper.ps1

$username = $env:LOCAL_ADMIN_USERNAME
$password = $env:LOCAL_ADMIN_PASSWORD

$cisScript = 'C:\Windows\Temp\cis-harden.ps1'

$NewLocalAdmin         = $username
$NewLocalAdminPassword = ConvertTo-SecureString $password -AsPlainText -Force

function global:Read-Host {
    param(
        [string]$Prompt,
        [switch]$AsSecureString
    )
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

try {
    . $cisScript
    Write-Host 'CIS hardening completed.'
} catch {
    Write-Host "WARNING: $_"
} finally {
    Remove-Item $cisScript -Force -ErrorAction SilentlyContinue
}

exit 0
