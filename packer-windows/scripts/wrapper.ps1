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

& "C:\Windows\Temp\cis-harden-patched.ps1"

Remove-Item "C:\Windows\Temp\cis-harden-patched.ps1" -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Windows\Temp\cis-harden.ps1" -Force -ErrorAction SilentlyContinue
