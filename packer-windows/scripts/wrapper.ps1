# wrapper.ps1

# 1. Retrieve credentials and securely destroy the file immediately
$creds = Get-Content 'C:\Windows\PackerBuild\creds.txt'
$username = $creds[0]
$password = $creds[1]
Remove-Item 'C:\Windows\PackerBuild\creds.txt' -Force -ErrorAction SilentlyContinue

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
    # Ignored: Sysprep handles the final shutdown.
}

function global:Stop-Computer {
    param([switch]$Force)
    # Ignored.
}

# --- Execution and Final Seal ---
try {
    . $cisScript
} catch {
    # Errors are trapped silently in the background task
} 

# Execute Sysprep to seal the Golden Image
& $env:SystemRoot\System32\Sysprep\Sysprep.exe /oobe /generalize /quiet /quit

exit 0
