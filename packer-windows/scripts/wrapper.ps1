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
    Write-Host 'Restart-Computer suppressed - Sysprep handles shutdown.'
}

function global:Stop-Computer {
    param([switch]$Force)
    Write-Host 'Stop-Computer suppressed.'
}

# --- Execution and Final Seal ---
try {
    Write-Host 'Starting CIS Hardening script...'
    . $cisScript
    Write-Host 'CIS hardening script finished.'
} catch {
    Write-Host "WARNING: CIS script threw an error: $_"
} finally {
    Write-Host 'Executing Sysprep directly from wrapper...'
    
    # Clean up the script file before sysprep seals the image
    Remove-Item $cisScript -Force -ErrorAction SilentlyContinue

    # Run Sysprep immediately
    & $env:SystemRoot\System32\Sysprep\Sysprep.exe /oobe /generalize /quiet /quit
    
    # Wait for Sysprep to complete. When the VM powers off, Packer's connection severs cleanly.
    while($true) { 
        $imageState = (Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State -ErrorAction SilentlyContinue).ImageState
        if($imageState -ne 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') { 
            Start-Sleep -s 10 
        } else { 
            Write-Host 'Sysprep complete. Waiting for Azure VM shutdown...'
            break 
        } 
    }
}

exit 0
