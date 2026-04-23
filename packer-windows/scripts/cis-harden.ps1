# ./packer-windows/scripts/cis-harden.ps1
# Apply CIS Level 1 hardening for Windows Server 2022
# This is where you apply GPO settings, service configs, etc.

Write-Host "Applying CIS Level 1 hardening..."

# Example: Disable Guest account (CIS 2.3.1.2)
net user Guest /active:no

# Example: Set minimum password length (CIS 1.1.4)
net accounts /minpwlen:14

# Add the rest of your CIS controls here...
