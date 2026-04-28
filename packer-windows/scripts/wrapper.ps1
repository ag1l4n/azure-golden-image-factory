# wrapper.ps1

$username = $env:LOCAL_ADMIN_USERNAME
$password = $env:LOCAL_ADMIN_PASSWORD
$cisScript = 'C:\Windows\PackerBuild\cis-harden.ps1'

# --- Function Overrides for Automation ---
function global:Read-Host {
    param(
        [string]$Prompt,
        [switch]$AsSecureString
    )
    if ($AsSecureString) {
        return (ConvertTo-SecureString $password -AsPlainText -Force)
    }
    return $password
}

function global:Restart-Computer {
    param([switch]$Force, [int]$Delay)
    Write-Host 'Restart-Computer suppressed - Sysprep handles final state.'
}

function global:Stop-Computer {
    param([switch]$Force)
    Write-Host 'Stop-Computer suppressed.'
}

# --- Execution and Final Seal ---
try {
    Write-Host 'Starting CIS Hardening script as SYSTEM...'
    . $cisScript
    Write-Host 'CIS hardening script finished.'
} catch {
    Write-Host "WARNING: CIS script threw an error: $_"
} finally {
    Write-Host 'Executing Sysprep directly from wrapper...'
    
    # Run Sysprep immediately in /quit mode (Prepares OS, but does not kill Packer's session)
    & $env:SystemRoot\System32\Sysprep\Sysprep.exe /oobe /generalize /quiet /quit
    
    Write-Host 'Waiting for Sysprep generalization to complete...'
    while($true) { 
        $imageState = (Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State -ErrorAction SilentlyContinue).ImageState
        if($imageState -eq 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') { 
            Write-Host 'Sysprep complete. Exiting gracefully to trigger Azure capture.'
            break 
        } 
        Start-Sleep -Seconds 10 
    }
}

exit 0
