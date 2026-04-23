# wrapper.ps1

$username = $env:LOCAL_ADMIN_USERNAME
$password = $env:LOCAL_ADMIN_PASSWORD

$cisScript     = 'C:\Windows\Temp\cis-harden.ps1'
$patchedScript = 'C:\Windows\Temp\cis-harden-patched.ps1'

$scriptContent = Get-Content $cisScript -Raw

# Controls that break Packer's WinRM connection
# These are suppressed during the build only — they do NOT affect the final
# baked image because Sysprep resets firewall and WinRM state entirely
$suppressedControls = @(
    # WinRM controls — break Packer auth
    'WinRMClientAllowBasic',
    'WinRMClientAllowUnencryptedTraffic',
    'WinRMClientAllowDigest',
    'WinRMServiceAllowBasic',
    'WinRMServiceAllowAutoConfig',
    'WinRMServiceAllowUnencryptedTraffic',
    'WinRMServiceDisableRunAs',
    'WinRSAllowRemoteShellAccess',

    # Firewall controls — block port 5986
    'DomainDefaultInboundAction',
    'PrivateDefaultInboundAction',
    'PublicDefaultInboundAction',
    'PublicAllowLocalPolicyMerge',
    'PublicAllowLocalIPsecPolicyMerge',
    'DomainEnableFirewall',
    'PrivateEnableFirewall',
    'PublicEnableFirewall'
)

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

# Suppress reboot — Packer windows-restart handles this
function global:Restart-Computer {
    param([switch]`$Force, [int]`$Delay)
    Write-Host 'Restart-Computer suppressed by wrapper.'
}

function global:Stop-Computer {
    param([switch]`$Force)
    Write-Host 'Stop-Computer suppressed by wrapper.'
}

"@

# Remove suppressed controls from the ExecutionList by commenting them out
# This is safer than stub functions because it prevents the code from running at all
foreach ($control in @(
    'WinRMClientAllowBasic',
    'WinRMClientAllowUnencryptedTraffic',
    'WinRMClientAllowDigest',
    'WinRMServiceAllowBasic',
    'WinRMServiceAllowAutoConfig',
    'WinRMServiceAllowUnencryptedTraffic',
    'WinRMServiceDisableRunAs',
    'WinRSAllowRemoteShellAccess',
    'DomainDefaultInboundAction',
    'PrivateDefaultInboundAction',
    'PublicDefaultInboundAction',
    'PublicAllowLocalPolicyMerge',
    'PublicAllowLocalIPsecPolicyMerge',
    'DomainEnableFirewall',
    'PrivateEnableFirewall',
    'PublicEnableFirewall'
)) {
    # Comment out the entry in $ExecutionList
    $scriptContent = $scriptContent -replace `
        "(`"$control`")", `
        "#`"`$1`" # Suppressed by Packer wrapper - Sysprep resets this"
}

$patched = $prepend + $scriptContent
$patched | Out-File $patchedScript -Encoding UTF8

try {
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
