# =============================================================================
# sysprep.ps1
#
# Backs up ALL CIS policy state before generalize, then registers a first-boot
# scheduled task to restore everything. The backup now covers three layers:
#   1. secedit  — account policies, user rights, security options
#   2. auditpol — advanced audit policy
#   3. reg export — SOFTWARE\Policies\Microsoft and LSA registry hive
#      (secedit does NOT cover these; they hold all section 18.x controls)
# =============================================================================

Write-Host "Locking down UAC network logon before sysprep..."
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
if (!(Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
Set-ItemProperty -Path $regPath -Name "LocalAccountTokenFilterPolicy" -Value 0 -Type DWord -Force

$scriptsPath = "C:\Windows\Setup\Scripts"
if (!(Test-Path $scriptsPath)) { New-Item -ItemType Directory -Force -Path $scriptsPath | Out-Null }

# ── Layer 1: secedit (account policies, user rights, security options)
Write-Host "Backing up secedit security policy..."
secedit.exe /export /cfg "$scriptsPath\cis-secpol.inf" /quiet

# ── Layer 2: auditpol (advanced audit subcategories)
Write-Host "Backing up audit policy..."
auditpol.exe /backup /file:"$scriptsPath\cis-auditpol.csv"

# ── Layer 3: registry export (all section 18.x Administrative Template controls)
# This is the layer the original sysprep was missing. secedit does NOT export
# HKLM\SOFTWARE\Policies\Microsoft — those keys must be saved separately.
Write-Host "Backing up SOFTWARE\Policies\Microsoft registry hive..."
reg export "HKLM\SOFTWARE\Policies\Microsoft" "$scriptsPath\microsoft-policies.reg" /y

Write-Host "Backing up LSA registry hive..."
reg export "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" "$scriptsPath\lsa-policies.reg" /y

Write-Host "Backing up WinRM policy registry keys..."
reg export "HKLM\SOFTWARE\Policies\Microsoft\Windows\WinRM" "$scriptsPath\winrm-policies.reg" /y

# ── Build the RestoreCIS.ps1 script that runs on first boot
$restoreScript = "$scriptsPath\RestoreCIS.ps1"
$psCommand = @'
# ── Restore secedit security policy
secedit.exe /configure /db $env:windir\security\local.sdb /cfg C:\Windows\Setup\Scripts\cis-secpol.inf /overwrite /quiet

# ── Restore audit policy
auditpol.exe /restore /file:C:\Windows\Setup\Scripts\cis-auditpol.csv

# ── Restore SOFTWARE\Policies\Microsoft registry hive (section 18.x controls)
# This is what the original restore was missing.
if (Test-Path "C:\Windows\Setup\Scripts\microsoft-policies.reg") {
    reg import "C:\Windows\Setup\Scripts\microsoft-policies.reg"
}

# ── Restore LSA policy keys
if (Test-Path "C:\Windows\Setup\Scripts\lsa-policies.reg") {
    reg import "C:\Windows\Setup\Scripts\lsa-policies.reg"
}

# ── Restore WinRM policy keys (backed up separately for safety)
if (Test-Path "C:\Windows\Setup\Scripts\winrm-policies.reg") {
    reg import "C:\Windows\Setup\Scripts\winrm-policies.reg"
}

# ── Self-destruct after successful restore
Unregister-ScheduledTask -TaskName 'RestoreCISPolicies' -Confirm:$false
'@
Out-File -FilePath $restoreScript -InputObject $psCommand -Encoding ASCII -Force

# ── Register the scheduled task
$action    = New-ScheduledTaskAction -Execute 'powershell.exe' `
               -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File $restoreScript"
$trigger   = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" `
               -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName 'RestoreCISPolicies' `
    -Action $action -Trigger $trigger -Principal $principal

Write-Host "Running Sysprep..."
& $env:SystemRoot\System32\Sysprep\Sysprep.exe /oobe /generalize /quiet /quit /mode:vm
