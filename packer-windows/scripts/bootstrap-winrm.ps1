Write-Output "Bootstrapping WinRM for Packer..."
winrm quickconfig -q
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/service/auth '@{Basic="true"}'
Set-NetFirewallRule -Name "WINRM-HTTP-In-TCP" -RemoteAddress Any
Write-Output "Installing OpenSSH Server before CIS hardening blocks Windows Update..."
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Set-Service -Name sshd -StartupType 'Automatic'
Start-Service -Name sshd
