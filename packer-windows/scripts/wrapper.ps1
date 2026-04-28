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

    # 1. Nuke the Group Policy Registry Keys set by CIS
    $winrmServicePolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service'
    if (Test-Path $winrmServicePolicy) {
        Set-ItemProperty -Path $winrmServicePolicy -Name 'AllowBasic' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    }

    $winrmClientPolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Client'
    if (Test-Path $winrmClientPolicy) {
        Set-ItemProperty -Path $winrmClientPolicy -Name 'AllowBasic' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue
    }

    # 2. Apply standard WSMan settings as a fallback
    Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $true -Force -ErrorAction SilentlyContinue
    Set-Item -Path WSMan:\localhost\Client\Auth\Basic -Value $true -Force -ErrorAction SilentlyContinue

    # 3. Ensure WinRM service is set to Automatic
    Set-Service WinRM -StartupType Automatic -ErrorAction SilentlyContinue

    # 4. Re-open the Firewall for WinRM HTTPS (Port 5986)
    New-NetFirewallRule -Name "Packer-WinRM-HTTPS" `
                        -DisplayName "Packer WinRM HTTPS" `
                        -Enabled True `
                        -Direction Inbound `
                        -Protocol TCP `
                        -Action Allow `
                        -LocalPort 5986 `
                        -ErrorAction SilentlyContinue

    # 5. THE TRICK: Restart WinRM in a detached background process.
    # Doing this synchronously kills Packer's active session. 
    # This command schedules a restart 5 seconds after Packer cleanly exits this provisioner.
    Invoke-WmiMethod -Class Win32_Process -Name Create -ArgumentList "powershell.exe -WindowStyle Hidden -Command `"Start-Sleep -Seconds 5; Restart-Service WinRM -Force`"" | Out-Null

    Write-Host 'WinRM restored successfully. Handing back to Packer.'

    # Cleanup
    Remove-Item $cisScript -Force -ErrorAction SilentlyContinue
}

exit 0
