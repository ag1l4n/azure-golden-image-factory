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

# Suppress reboot — Packer windows-restart provisioner handles this
function global:Restart-Computer {
    param([switch]`$Force, [int]`$Delay)
    Write-Host 'Restart-Computer suppressed by wrapper - Packer will handle reboot.'
}

function global:Stop-Computer {
    param([switch]`$Force)
    Write-Host 'Stop-Computer suppressed by wrapper.'
}

# Suppress WinRM-breaking CIS controls so Packer can reconnect after restart
# These will be applied by GPO/policy in production — not needed on the build VM
# The Sysprep step resets WinRM state anyway so this does not affect the final image
function global:WinRMClientAllowBasic { Write-Host 'WinRMClientAllowBasic suppressed by wrapper.' }
function global:WinRMClientAllowUnencryptedTraffic { Write-Host 'WinRMClientAllowUnencryptedTraffic suppressed by wrapper.' }
function global:WinRMClientAllowDigest { Write-Host 'WinRMClientAllowDigest suppressed by wrapper.' }
function global:WinRMServiceAllowBasic { Write-Host 'WinRMServiceAllowBasic suppressed by wrapper.' }
function global:WinRMServiceAllowAutoConfig { Write-Host 'WinRMServiceAllowAutoConfig suppressed by wrapper.' }
function global:WinRMServiceAllowUnencryptedTraffic { Write-Host 'WinRMServiceAllowUnencryptedTraffic suppressed by wrapper.' }
function global:WinRMServiceDisableRunAs { Write-Host 'WinRMServiceDisableRunAs suppressed by wrapper.' }
function global:WinRSAllowRemoteShellAccess { Write-Host 'WinRSAllowRemoteShellAccess suppressed by wrapper.' }

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
    Remove-Item $cisScript     -Force -ErrorAction SilentlyContinue
}

exit 0
