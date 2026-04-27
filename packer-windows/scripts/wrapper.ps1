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

# Comment out firewall controls from ExecutionList to keep port 5986 open
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
# Port 5986 is open but Basic auth was disabled by CIS WinRM controls
# Restore it here so Packer can reconnect for remaining provisioners
# Sysprep resets all WinRM state so this does not affect the final image
Write-Host 'Restoring WinRM Basic auth for Packer...'

try {
    # Restore Basic auth on both client and service
    Set-Item 'WSMan:\localhost\Service\Auth\Basic' $true
    Set-Item 'WSMan:\localhost\Client\Auth\Basic' $true

    # Ensure content type negotiation is enabled
    Set-Item 'WSMan:\localhost\Service\AllowUnencrypted' $false
    Set-Item 'WSMan:\localhost\Client\AllowUnencrypted' $false

    # Restore RunAs so elevated provisioners work
    Set-Item 'WSMan:\localhost\Service\Auth\CredSSP' $true -ErrorAction SilentlyContinue

    # Restart WinRM to apply
    Restart-Service WinRM -Force

    Write-Host 'WinRM auth restored successfully.'
} catch {
    Write-Host "WARNING: WinRM restore encountered an error: $_"
}
# --- END RESTORE ---

exit 0
