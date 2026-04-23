# Pull credentials from environment variables set by Packer
$NewLocalAdmin = $env:LOCAL_ADMIN_USERNAME
$NewLocalAdminPassword = ConvertTo-SecureString $env:LOCAL_ADMIN_PASSWORD -AsPlainText -Force

# Read the original CIS script content
$scriptContent = Get-Content "C:\Windows\Temp\cis-harden.ps1" -Raw

# Replace the Read-Host prompt line with a pre-set SecureString
# This targets the specific line that causes the interactive prompt
$scriptContent = $scriptContent -replace `
    '\$NewLocalAdminPassword\s*=\s*Read-Host[^\n]*', `
    "`$NewLocalAdminPassword = ConvertTo-SecureString '$password' -AsPlainText -Force"

# Also pre-set the username in case the script re-declares it
$scriptContent = $scriptContent -replace `
    '\$NewLocalAdmin\s*=\s*"User"', `
    "`$NewLocalAdmin = '$username'"

# Write the patched version to a temp location
$scriptContent | Out-File "C:\Windows\Temp\cis-harden-patched.ps1" -Encoding UTF8

# Execute the patched script
& "C:\Windows\Temp\cis-harden-patched.ps1"

# Clean up — don't leave patched script with password on disk
Remove-Item "C:\Windows\Temp\cis-harden-patched.ps1" -Force
Remove-Item "C:\Windows\Temp\cis-harden.ps1" -Force
