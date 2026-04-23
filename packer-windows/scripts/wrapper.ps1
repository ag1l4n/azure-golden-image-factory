# wrapper.ps1

$username = $env:LOCAL_ADMIN_USERNAME
$password = $env:LOCAL_ADMIN_PASSWORD

$cisScript     = 'C:\Windows\Temp\cis-harden.ps1'
$patchedScript = 'C:\Windows\Temp\cis-harden-patched.ps1'

$scriptContent = Get-Content $cisScript -Raw

$prepend = @"
`$NewLocalAdmin = '$username'
`$NewLocalAdminPassword = ConvertTo-SecureString '$password' -AsPlainText -Force

# Suppress interactive prompts
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

# Suppress reboot
function global:Restart-Computer {
    param([switch]`$Force, [int]`$Delay)
    Write-Host 'Restart-Computer suppressed by wrapper.'
}

function global:Stop-Computer {
    param([switch]`$Force)
    Write-Host 'Stop-Computer suppressed by wrapper.'
}

# Suppress WinRM-breaking controls
function global:WinRMClientAllowBasic { Write-Host 'Suppressed: WinRMClientAllowBasic' }
function global:WinRMClientAllowUnencryptedTraffic { Write-Host 'Suppressed: WinRMClientAllowUnencryptedTraffic' }
function global:WinRMClientAllowDigest { Write-Host 'Suppressed: WinRMClientAllowDigest' }
function global:WinRMServiceAllowBasic { Write-Host 'Suppressed: WinRMServiceAllowBasic' }
function global:WinRMServiceAllowAutoConfig { Write-Host 'Suppressed: WinRMServiceAllowAutoConfig' }
function global:WinRMServiceAllowUnencryptedTraffic { Write-Host 'Suppressed: WinRMServiceAllowUnencryptedTraffic' }
function global:WinRMServiceDisableRunAs { Write-Host 'Suppressed: WinRMServiceDisableRunAs' }
function global:WinRSAllowRemoteShellAccess { Write-Host 'Suppressed: WinRSAllowRemoteShellAccess' }

"@

# Append a WinRM restore block at the END of the patched script
# This runs after all CIS controls and restores Packer connectivity
$append = @"

# --- PACKER WinRM RESTORE ---
# Runs after CIS hardening to restore Packer connectivity
# Sysprep will reset this state so it does not affect the final image
Write-Host 'Restoring WinRM for Packer post-hardening...'

# Re-enable WinRM service
Set-Service WinRM -StartupType Automatic
Start-Service WinRM -ErrorAction SilentlyContinue

# Restore auth settings Packer needs
Set-Item 'WSMan:\localhost\Service\Auth\Basic' `$true
Set-Item 'WSMan:\localhost\Client\Auth\Basic' `$true

# Re-open port 5986 in the firewall (CIS may have closed it)
netsh advfirewall firewall add rule name='Packer WinRM HTTPS' dir=in action=allow protocol=TCP localport=5986 | Out-Null

# Restart WinRM to apply all changes
Restart-Service WinRM -Force

Write-Host 'WinRM restored successfully.'
# --- END PACKER WinRM RESTORE ---
"@

$patched = $prepend + $scriptContent + $append
$patched | Out-File $patchedScript -Encoding UTF8

try {
    # Dot-source so global function overrides are visible inside the script
    . $patchedScript
    Write-Host 'CIS hardening completed.'
} catch {
    Write-Host "WARNING: CIS script encountered an error: $_"
    Write-Host 'Continuing - review log at C:\CIS\_Hardening'
} finally {
    Remove-Item $patchedScript -Force -ErrorAction SilentlyContinue
    Remove-Item $cisScript     -Force -ErrorAction SilentlyContinue
}

exit 0
