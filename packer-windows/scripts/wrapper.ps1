# wrapper.ps1

$username = $env:LOCAL_ADMIN_USERNAME
$password = $env:LOCAL_ADMIN_PASSWORD

$cisScript     = 'C:\Windows\Temp\cis-harden.ps1'
$patchedScript = 'C:\Windows\Temp\cis-harden-patched.ps1'

# Read script line by line — more reliable than raw regex on full content
$lines = Get-Content $cisScript

# ALL controls that touch WinRM or firewall — comment out entire line if it contains these
$suppressedControls = @(
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
    'PublicEnableFirewall',
    'DomainLogFilePath',
    'DomainLogFileSize',
    'DomainLogDroppedPackets',
    'DomainLogSuccessfulConnections',
    'PrivateLogFilePath',
    'PrivateLogFileSize',
    'PrivateLogDroppedPackets',
    'PrivateLogSuccessfulConnections',
    'PublicLogFilePath',
    'PublicLogFileSize',
    'PublicLogDroppedPackets',
    'PublicLogSuccessfulConnections'
)

$patchedLines = foreach ($line in $lines) {
    $suppressed = $false
    foreach ($control in $suppressedControls) {
        # Match any line in the ExecutionList that contains this control name
        # Handles formats like: "ControlName", #comment
        #                   or: "ControlName" #comment
        #                   or: "ControlName",
        if ($line -match "^\s*`"$control`"") {
            Write-Host "Suppressing control: $control"
            "    #`"$control`" # Suppressed by Packer wrapper - Sysprep resets this state"
            $suppressed = $true
            break
        }
    }
    if (-not $suppressed) {
        $line
    }
}

$prepend = @"
`$NewLocalAdmin = '$username'
`$NewLocalAdminPassword = ConvertTo-SecureString '$password' -AsPlainText -Force

function global:Read-Host {
    param(
        [string]`$Prompt,
        [switch]`$AsSecureString
    )
    Write-Host "Read-Host suppressed: `$Prompt"
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

# Write prepend + patched lines
$prepend | Out-File $patchedScript -Encoding UTF8
$patchedLines | Out-File $patchedScript -Encoding UTF8 -Append

# Verify suppression worked before running
$verification = Get-Content $patchedScript | Where-Object { $_ -match 'WinRMServiceAllowBasic|WinRMClientAllowBasic' }
Write-Host "WinRM control lines after patch:"
$verification | ForEach-Object { Write-Host $_ }

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
