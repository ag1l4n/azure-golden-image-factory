# wrapper.ps1

$username = $env:LOCAL_ADMIN_USERNAME
$password = $env:LOCAL_ADMIN_PASSWORD

# Read the original script
$scriptContent = Get-Content "C:\Windows\Temp\cis-harden.ps1" -Raw

# Prepend variable assignments at the very top so they are declared
# before the script body runs — this wins over any Read-Host later
# because we also suppress all Read-Host calls entirely
$prepend = @"
`$NewLocalAdmin = '$username'
`$NewLocalAdminPassword = ConvertTo-SecureString '$password' -AsPlainText -Force

# Override Read-Host globally to prevent any interactive prompts
function global:Read-Host {
    param(`$Prompt)
    Write-Host "Read-Host suppressed by wrapper: `$Prompt"
    # Return the password if it looks like a password prompt, else empty string
    if (`$Prompt -like '*password*') {
        return '$password'
    }
    return ''
}

"@

$patched = $prepend + $scriptContent

$patched | Out-File "C:\Windows\Temp\cis-harden-patched.ps1" -Encoding UTF8

# Run the patched script
& "C:\Windows\Temp\cis-harden-patched.ps1"

# Clean up immediately
Remove-Item "C:\Windows\Temp\cis-harden-patched.ps1" -Force -ErrorAction SilentlyContinue
Remove-Item "C:\Windows\Temp\cis-harden.ps1" -Force -ErrorAction SilentlyContinue
