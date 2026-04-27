# wrapper.ps1

$username = $env:LOCAL_ADMIN_USERNAME
$password = $env:LOCAL_ADMIN_PASSWORD

$cisScript = 'C:\Windows\Temp\cis-harden.ps1'

# Pre-set variables the CIS script needs
$NewLocalAdmin = $username
$NewLocalAdminPassword = ConvertTo-SecureString $password -AsPlainText -Force

# Suppress interactive prompts
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

# Suppress reboot — Packer windows-restart handles this
function global:Restart-Computer {
    param([switch]$Force, [int]$Delay)
    Write-Host 'Restart-Computer suppressed by wrapper.'
}

function global:Stop-Computer {
    param([switch]$Force)
    Write-Host 'Stop-Computer suppressed by wrapper.'
}

# Dot-source so all overrides are visible inside the script
try {
    . $cisScript
    Write-Host 'CIS hardening completed.'
} catch {
    Write-Host "WARNING: CIS script encountered an error: $_"
    Write-Host 'Continuing - review log at C:\CIS\_Hardening'
} finally {
    Remove-Item $cisScript -Force -ErrorAction SilentlyContinue
}

exit 0
