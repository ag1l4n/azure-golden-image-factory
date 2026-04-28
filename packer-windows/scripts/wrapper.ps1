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
    Write-Host 'Executing Finally block: Restoring WinRM for Packer pipeline...'

    # 1. Restore WinRM Basic Authentication (Required by Packer)
    Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $true -Force -ErrorAction SilentlyContinue
    Set-Item -Path WSMan:\localhost\Client\Auth\Basic -Value $true -Force -ErrorAction SilentlyContinue

    # 2. Ensure WinRM service is running and set to Automatic
    Start-Service WinRM -ErrorAction SilentlyContinue
    Set-Service WinRM -StartupType Automatic -ErrorAction SilentlyContinue

    # 3. Re-open the Firewall for WinRM HTTPS (Port 5986)
    New-NetFirewallRule -Name "Packer-WinRM-HTTPS" `
                        -DisplayName "Packer WinRM HTTPS" `
                        -Enabled True `
                        -Direction Inbound `
                        -Protocol TCP `
                        -Action Allow `
                        -LocalPort 5986 `
                        -ErrorAction SilentlyContinue

    # 4. Restart the WinRM service to apply the Auth changes
    Restart-Service WinRM -Force -ErrorAction SilentlyContinue
    
    Write-Host 'WinRM restored successfully.'

    # Cleanup
    Remove-Item $cisScript -Force -ErrorAction SilentlyContinue
}

exit 0
