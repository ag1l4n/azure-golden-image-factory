# wrapper.ps1

$username = $env:LOCAL_ADMIN_USERNAME
$password = $env:LOCAL_ADMIN_PASSWORD

$cisScript = 'C:\Windows\Temp\cis-harden.ps1'

# --- Function Overrides for Automation ---

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

# --- Execution and Safety Net ---

try {
    Write-Host 'Starting CIS Hardening script...'
    . $cisScript
    Write-Host 'CIS hardening script finished.'
} catch {
    Write-Host "WARNING: CIS script threw an error: $_"
} finally {
    Write-Host 'Executing Finally block: Obliterating CIS WinRM blocks for Packer...'

    # 1. Completely nuke the WinRM Group Policy registry tree to unlock local config
    $winrmPolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM'
    if (Test-Path $winrmPolicyPath) {
        Remove-Item -Path $winrmPolicyPath -Recurse -Force -ErrorAction SilentlyContinue
    }

    # 2. Dynamically apply Basic Auth to the running service (Bypasses the need for a restart)
    # Note: cmd.exe is used here to avoid PowerShell parsing issues with the @{} syntax
    cmd.exe /c "winrm set winrm/config/service/auth @{Basic=`"true`"}"
    cmd.exe /c "winrm set winrm/config/client/auth @{Basic=`"true`"}"

    # 3. Ensure the active Packer user hasn't been stripped of remote access rights
    Add-LocalGroupMember -Group 'Administrators' -Member $username -ErrorAction SilentlyContinue
    Add-LocalGroupMember -Group 'Remote Management Users' -Member $username -ErrorAction SilentlyContinue

    # 4. Guarantee the Firewall rule is open for Packer's HTTPS connection
    New-NetFirewallRule -Name "Packer-WinRM-HTTPS" `
                        -DisplayName "Packer WinRM HTTPS" `
                        -Enabled True `
                        -Direction Inbound `
                        -Protocol TCP `
                        -Action Allow `
                        -LocalPort 5986 `
                        -Force `
                        -ErrorAction SilentlyContinue

    Write-Host 'WinRM restored dynamically. Handing back to Packer.'

    # Cleanup
    Remove-Item $cisScript -Force -ErrorAction SilentlyContinue
}

exit 0
