# =============================================================================
# finalize.ps1
# =============================================================================

function Set-Reg {
    param($Path, $Name, $Value, $Type = 'DWord')
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
    Write-Output "SET [$Type] $Path\$Name = $Value"
}

Write-Output "=== Part 1: Non-WinRM CIS controls ==="
Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" "RestrictReceivingNTLMTraffic" 2

Write-Output "Installing OpenSSH Server..."
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'

$gpFWPath = "HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall\FirewallRules"
if (-not (Test-Path $gpFWPath)) {
    New-Item -Path $gpFWPath -Force | Out-Null
}
Set-ItemProperty -Path $gpFWPath `
    -Name "OpenSSH-Server-Inbound-TCP22" `
    -Value "v2.31|Action=Allow|Active=TRUE|Dir=In|Protocol=6|LPort=22|Name=OpenSSH Server (sshd)|Desc=OpenSSH Server for pipeline scanning|" `
    -Type String -Force


Write-Output "=== Part 2: Backing up CIS policy state ==="
$scriptsPath = "C:\Windows\Setup\Scripts"
if (!(Test-Path $scriptsPath)) {
    New-Item -ItemType Directory -Force -Path $scriptsPath | Out-Null
}

secedit.exe /export /cfg "$scriptsPath\cis-secpol.inf" /quiet
auditpol.exe /backup /file:"$scriptsPath\cis-auditpol.csv"
reg export "HKLM\SOFTWARE\Policies\Microsoft" "$scriptsPath\microsoft-policies.reg" /y
reg export "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" "$scriptsPath\lsa-policies.reg" /y

$restoreScript = "$scriptsPath\RestoreCIS.ps1"
@'
Start-Transcript -Path "C:\Windows\Setup\Scripts\RestoreCIS.log"

# 1. Restore secedit security policy
secedit.exe /configure /db $env:windir\security\local.sdb /cfg C:\Windows\Setup\Scripts\cis-secpol.inf /overwrite /quiet

# 2. Restore audit policy
auditpol.exe /restore /file:C:\Windows\Setup\Scripts\cis-auditpol.csv

# 3. Restore SOFTWARE\Policies\Microsoft registry hive (Firewall & Section 18.x)
if (Test-Path "C:\Windows\Setup\Scripts\microsoft-policies.reg") {
    reg import "C:\Windows\Setup\Scripts\microsoft-policies.reg"
}
if (Test-Path "C:\Windows\Setup\Scripts\lsa-policies.reg") {
    reg import "C:\Windows\Setup\Scripts\lsa-policies.reg"
}

# -----------------------------------------------------------------------------
# CRITICAL FIX 1: Restart Firewall so it actively reads the GP registry rule!
# -----------------------------------------------------------------------------
$svc = Get-Service mpssvc
while ($svc.Status -ne 'Running') { Start-Sleep -Seconds 2; $svc = Get-Service mpssvc }
Restart-Service -Name mpssvc -Force

# -----------------------------------------------------------------------------
# CRITICAL FIX 2: Ensure SSH starts AFTER the firewall is open
# -----------------------------------------------------------------------------
Set-Service -Name sshd -StartupType Automatic -ErrorAction SilentlyContinue
Start-Service -Name sshd -ErrorAction SilentlyContinue

Unregister-ScheduledTask -TaskName 'RestoreCISPolicies' -Confirm:$false
Stop-Transcript
'@ | Out-File -FilePath $restoreScript -Encoding ASCII -Force

$action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File $restoreScript"
$trigger   = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName 'RestoreCISPolicies' -Action $action -Trigger $trigger -Principal $principal -Force


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
# -----------------------------------------------------------------------------
# CRITICAL FIX 3: Start-Process -Wait guarantees Packer doesn't capture a corrupt VM
# -----------------------------------------------------------------------------
Start-Process -FilePath "$env:SystemRoot\System32\Sysprep\Sysprep.exe" -ArgumentList "/oobe /generalize /quiet /quit /mode:vm" -Wait -NoNewWindow

Write-Output "=== finalize.ps1 complete ==="
