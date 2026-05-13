# =============================================================================
# finalize.ps1
# =============================================================================

function Set-Reg {
    param($Path, $Name, $Value, $Type = 'DWord')
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
}

Write-Output "=== Part 1: Install OpenSSH & Network Safe Firewall Rule ==="
Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" "RestrictReceivingNTLMTraffic" 2

Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Set-Service -Name sshd -StartupType 'Automatic'

# This native rule survives Sysprep and takes effect immediately (No Firewall Restart needed!)
New-NetFirewallRule -Name "OpenSSH-Pipeline" -DisplayName "OpenSSH Server (sshd)" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -ErrorAction SilentlyContinue


Write-Output "=== Part 2: Backing up CIS policy state ==="
$scriptsPath = "C:\Windows\Setup\Scripts"
if (!(Test-Path $scriptsPath)) { New-Item -ItemType Directory -Force -Path $scriptsPath | Out-Null }

secedit.exe /export /cfg "$scriptsPath\cis-secpol.inf" /quiet
auditpol.exe /backup /file:"$scriptsPath\cis-auditpol.csv"
reg export "HKLM\SOFTWARE\Policies\Microsoft" "$scriptsPath\microsoft-policies.reg" /y
reg export "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" "$scriptsPath\lsa-policies.reg" /y

$restoreScript = "$scriptsPath\RestoreCIS.ps1"
@'
Start-Transcript -Path "C:\Windows\Setup\Scripts\RestoreCIS.log"

# Fix SID Corruption so sshd can start cleanly
Remove-Item -Path "C:\ProgramData\ssh\ssh_host_*_key*" -Force -ErrorAction SilentlyContinue

secedit.exe /configure /db $env:windir\security\local.sdb /cfg C:\Windows\Setup\Scripts\cis-secpol.inf /overwrite /quiet
auditpol.exe /restore /file:C:\Windows\Setup\Scripts\cis-auditpol.csv

if (Test-Path "C:\Windows\Setup\Scripts\microsoft-policies.reg") { reg import "C:\Windows\Setup\Scripts\microsoft-policies.reg" }
if (Test-Path "C:\Windows\Setup\Scripts\lsa-policies.reg") { reg import "C:\Windows\Setup\Scripts\lsa-policies.reg" }

# Start OpenSSH natively (Firewall is already open)
Start-Service -Name sshd -ErrorAction SilentlyContinue

Unregister-ScheduledTask -TaskName 'RestoreCISPolicies' -Confirm:$false
Stop-Transcript
'@ | Out-File -FilePath $restoreScript -Encoding ASCII -Force

$action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File $restoreScript"
# Adding a 15-second delay so Azure Agent gets CPU priority first
$trigger   = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName 'RestoreCISPolicies' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force


Write-Output "=== Part 3: WinRM CIS controls (locks WinRM for new connections) ==="
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Client" "AllowBasic" 0
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Client" "AllowUnencryptedTraffic" 0
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Client" "AllowDigest" 0
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service" "AllowBasic" 0
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service" "AllowAutoConfig" 0
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service" "AllowUnencryptedTraffic" 0
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service" "DisableRunAs" 1
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service\WinRS" "AllowRemoteShellAccess" 0


Write-Output "=== Part 4: Sysprep ==="
$uacPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
Set-ItemProperty -Path $uacPath -Name "LocalAccountTokenFilterPolicy" -Value 0 -Type DWord -Force

Write-Output "Running Sysprep..."
Start-Process -FilePath "$env:SystemRoot\System32\Sysprep\Sysprep.exe" -ArgumentList "/oobe /generalize /quiet /quit /mode:vm" -Wait -NoNewWindow
