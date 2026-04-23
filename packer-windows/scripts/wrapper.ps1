# wrapper.ps1

$username = $env:LOCAL_ADMIN_USERNAME
$password = $env:LOCAL_ADMIN_PASSWORD

$cisScript    = 'C:\Windows\Temp\cis-harden.ps1'
$patchedScript = 'C:\Windows\Temp\cis-harden-patched.ps1'

$scriptContent = Get-Content $cisScript -Raw

$prepend = @"
`$NewLocalAdmin = '$username'
`$NewLocalAdminPassword = ConvertTo-SecureString '$password' -AsPlainText -Force

# Suppress all interactive prompts
function global:Read-Host {
    param(
        [string]`$Prompt,
        [switch]`$AsSecureString
    )
    Write-Host "Read-Host suppressed by wrapper: `$Prompt"
    if (`$AsSecureString) {
        return (ConvertTo-SecureString '$password' -AsPlainText -Force)
    }
    return '$password'
}

# Suppress reboot — Packer windows-restart provisioner handles this instead
function global:Restart-Computer {
    param([switch]`$Force, [int]`$Delay)
    Write-Host 'Restart-Computer suppressed by wrapper - Packer will handle reboot.'
}

# Also suppress shutdown command in case script uses it directly
function global:Stop-Computer {
    param([switch]`$Force)
    Write-Host 'Stop-Computer suppressed by wrapper.'
}

"@

$patched = $prepend + $scriptContent
$patched | Out-File $patchedScript -Encoding UTF8

try {
    & $patchedScript
    Write-Host 'CIS hardening completed.'
} catch {
    Write-Host "WARNING: CIS script encountered an error: $_"
    Write-Host 'Continuing build - review hardening log at C:\CIS\_Hardening'
} finally {
    Remove-Item $patchedScript -Force -ErrorAction SilentlyContinue
    Remove-Item $cisScript -Force -ErrorAction SilentlyContinue
}

exit 0
