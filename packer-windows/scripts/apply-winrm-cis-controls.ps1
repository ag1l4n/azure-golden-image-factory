Write-Output "Installing OpenSSH Server for Pipeline SCP access..."
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'
New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22

Write-Output "Applying WinRM CIS Controls..."
# CIS 18.9.102.2.2: Disable Basic authentication for WinRM
Set-Item -Path "WSMan:\localhost\Service\Auth\Basic" -Value $false
# CIS 18.9.103.1: Disable unencrypted WinRM
Set-Item -Path "WSMan:\localhost\Service\AllowUnencrypted" -Value $false

Write-Host "Applying UAC Network Logon Restrictions (Fixes windows-185)..."
# This strips administrative privileges from local accounts logging in over the network.
# Applied here at the end so it doesn't sever Packer's active Ansible WinRM session!
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
if (!(Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
Set-ItemProperty -Path $regPath -Name "LocalAccountTokenFilterPolicy" -Value 0 -Type DWord -Force
