# wrapper.ps1

$username = $env:LOCAL_ADMIN_USERNAME
$password = $env:LOCAL_ADMIN_PASSWORD

$cisScript     = 'C:\Windows\Temp\cis-harden.ps1'
$patchedScript = 'C:\Windows\Temp\cis-harden-patched.ps1'

$scriptContent = Get-Content $cisScript -Raw

$prepend = @"
`$NewLocalAdmin = '$username'
`$NewLocalAdminPassword = ConvertTo-SecureString '$password' -AsPlainText -Force

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

function global:Restart-Computer {
    param([switch]`$Force, [int]`$Delay)
    Write-Host 'Restart-Computer suppressed by wrapper.'
}

function global:Stop-Computer {
    param([switch]`$Force)
    Write-Host 'Stop-Computer suppressed by wrapper.'
}

"@

# Comment out firewall controls to keep port 5986 open
foreach ($control in @(
    'DomainDefaultInboundAction',
    'PrivateDefaultInboundAction',
    'PublicDefaultInboundAction',
    'PublicAllowLocalPolicyMerge',
    'PublicAllowLocalIPsecPolicyMerge',
    'DomainEnableFirewall',
    'PrivateEnableFirewall',
    'PublicEnableFirewall'
)) {
    $scriptContent = $scriptContent -replace `
        "(`"$control`")", `
        '#"$1" # Suppressed by Packer wrapper'
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

# --- RESTORE WINRM AUTH FOR PACKER ---
# The CIS script sets GPO registry keys that override WSMan:\ settings
# We must remove those policy keys directly — NOT restart WinRM (kills session)
Write-Host 'Restoring WinRM Basic auth for Packer...'

$policyPaths = @(
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Client',
    'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service'
)

foreach ($path in $policyPaths) {
    if (Test-Path $path) {
        # Remove the specific policy values that disable Basic auth
        Remove-ItemProperty -Path $path -Name 'AllowBasic'             -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $path -Name 'AllowUnencryptedTraffic' -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $path -Name 'AllowDigest'            -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $path -Name 'DisableRunAs'           -ErrorAction SilentlyContinue
        Write-Host "Cleared WinRM policy overrides at: $path"
    }
}

# Also clear WinRS policy
$winrsPolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\WinRS'
if (Test-Path $winrsPolicyPath) {
    Remove-ItemProperty -Path $winrsPolicyPath -Name 'AllowRemoteShellAccess' -ErrorAction SilentlyContinue
    Write-Host "Cleared WinRS policy overrides."
}

# Now set WSMan directly — with policy keys gone, these will take effect
Set-Item 'WSMan:\localhost\Service\Auth\Basic' $true -ErrorAction SilentlyContinue
Set-Item 'WSMan:\localhost\Client\Auth\Basic' $true  -ErrorAction SilentlyContinue

# Do NOT restart WinRM — that kills the current Packer session
# WinRM reads auth config per-request so changes take effect immediately
Write-Host 'WinRM policy overrides cleared. Packer can now reconnect.'
# --- END RESTORE ---

exit 0
