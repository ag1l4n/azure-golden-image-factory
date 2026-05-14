# =============================================================================
# finalize.ps1
# =============================================================================

function Set-Reg {
    param($Path, $Name, $Value, $Type = 'DWord')
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
}

Write-Output "=== Part 1: GP-level Firewall Rule for SSH ==="
Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" "RestrictReceivingNTLMTraffic" 2

$gpFWPath = "HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall\FirewallRules"
if (-not (Test-Path $gpFWPath)) { New-Item -Path $gpFWPath -Force | Out-Null }
Set-ItemProperty -Path $gpFWPath `
    -Name "OpenSSH-Server-Inbound-TCP22" `
    -Value "v2.31|Action=Allow|Active=TRUE|Dir=In|Protocol=6|LPort=22|Name=OpenSSH Server (sshd)|Desc=OpenSSH Server for pipeline scanning|" `
    -Type String -Force
Write-Output "GP firewall rule for port 22 written."


Write-Output "=== Part 2: Backing up CIS policy state ==="
$scriptsPath = "C:\Windows\Setup\Scripts"
if (!(Test-Path $scriptsPath)) { New-Item -ItemType Directory -Force -Path $scriptsPath | Out-Null }

secedit.exe /export /cfg "$scriptsPath\cis-secpol.inf" /quiet
auditpol.exe /backup /file:"$scriptsPath\cis-auditpol.csv"

$restoreScript = "$scriptsPath\RestoreCIS.ps1"
@'
Start-Transcript -Path "C:\Windows\Setup\Scripts\RestoreCIS.log"

# Remove stale SSH host keys left by sysprep so sshd can generate fresh ones
Remove-Item -Path "C:\ProgramData\ssh\ssh_host_*_key*" -Force -ErrorAction SilentlyContinue

# Restore security and audit policies natively
secedit.exe /configure /db $env:windir\security\local.sdb /cfg C:\Windows\Setup\Scripts\cis-secpol.inf /overwrite /quiet
auditpol.exe /restore /file:C:\Windows\Setup\Scripts\cis-auditpol.csv

# Generate fresh SSH keys and start the service
Start-Process -FilePath "C:\Windows\System32\OpenSSH\ssh-keygen.exe" -ArgumentList "-A" -NoNewWindow -Wait
Set-Service -Name sshd -StartupType Automatic -ErrorAction SilentlyContinue
Start-Service -Name sshd -ErrorAction SilentlyContinue

Unregister-ScheduledTask -TaskName 'RestoreCISPolicies' -Confirm:$false
Stop-Transcript
'@ | Out-File -FilePath $restoreScript -Encoding ASCII -Force

$action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File $restoreScript"
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
