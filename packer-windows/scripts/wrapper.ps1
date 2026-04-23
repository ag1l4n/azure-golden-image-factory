# wrapper.ps1

$username = $env:LOCAL_ADMIN_USERNAME
$password = $env:LOCAL_ADMIN_PASSWORD

$scriptContent = Get-Content "C:\Windows\Temp\cis-harden.ps1" -Raw

$prepend = @"
`$NewLocalAdmin = '$username'
`$NewLocalAdminPassword = ConvertTo-SecureString '$password' -AsPlainText -Force

# Override Read-Host to suppress all interactive prompts during unattended build
function global:Read-Host {
    param(
        [string]`$Prompt,
        [switch]`$AsSecureString
    )
    Write-Host "Read-Host suppressed by wrapper: `$Prompt"
    if (`$AsSecureString) {
        # Return a SecureString — required when script calls Read-Host -AsSecureString
        return (ConvertTo-SecureString '$password' -AsPlainText -Force)
    }
    # Return plain string for any other Read-Host calls
    return '$password'
}

"@

$patched = $prepend + $scriptContent
$patched | Out-File "C:\Windows\Temp\cis-harden-patched.ps1" -Encoding UTF8

try {
    & "C:\Windows\Temp\cis-harden-patched.ps1"
    Write-Host "CIS hardening completed."
} catch {
    # Log the error but don't propagate — some CIS controls fail on base images
    # due to missing components (e.g. domain-only settings on a standalone server)
    Write-Host "WARNING: CIS script encountered an error: $_"
    Write-Host "Continuing build — review hardening log at C:\CIS\_Hardening"
} finally {
    Remove-Item "C:\Windows\Temp\cis-harden-patched.ps1" -Force -ErrorAction SilentlyContinue
    Remove-Item "C:\Windows\Temp\cis-harden.ps1" -Force -ErrorAction SilentlyContinue
}

exit 0
