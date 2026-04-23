# Pull credentials from environment variables set by Packer
$NewLocalAdmin = $env:LOCAL_ADMIN_USERNAME
$NewLocalAdminPassword = ConvertTo-SecureString $env:LOCAL_ADMIN_PASSWORD -AsPlainText -Force

# Dot-source the CIS script so it runs in the SAME scope
# This means $NewLocalAdmin and $NewLocalAdminPassword are visible to it
. "C:\Windows\Temp\cis-harden.ps1"
