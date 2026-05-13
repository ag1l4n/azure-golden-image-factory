# =============================================================================
# finalize.ps1
#
# Runs as a single Packer provisioner step (Step 5). Replaces the former
# apply-winrm-cis-controls.ps1 and sysprep.ps1 provisioner steps.
#
# Why combined: apply-winrm-cis-controls.ps1 writes AllowBasic=0 which kills
# WinRM. sysprep.ps1 then failed because it needed a NEW WinRM connection.
# Running both in the same script means one WinRM session handles everything.
# Writing AllowBasic=0 doesn't kill the CURRENT session — only new connections.
# =============================================================================

function Set-Reg {
    param($Path, $Name, $Value, $Type = 'DWord')
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
    Write-Output "SET [$Type] $Path\$Name = $Value"
}

# =============================================================================
# PART 1: Non-WinRM CIS controls
# These are safe to apply anytime and don't affect the current WinRM session.
# =============================================================================

Write-Output "=== Part 1: Non-WinRM CIS controls ==="

# CIS 2.3.11.11 — Restore RestrictReceivingNTLMTraffic
# The Ansible post_task set this to 0 to keep Packer's session alive.
# Restore the CIS-required value of 2 now that we're in the final step.
Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" "RestrictReceivingNTLMTraffic" 2

# Install OpenSSH Server for the pipeline scan step (SCP access post-deploy)
Write-Output "Installing OpenSSH Server..."
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'
New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' `
    -DisplayName 'OpenSSH Server (sshd)' `
    -Enabled True -Direction Inbound -Protocol TCP `
    -Action Allow -LocalPort 22 -ErrorAction SilentlyContinue

# =============================================================================
# PART 2: Back up CIS policy state BEFORE sysprep wipes it
# Must happen before Part 3 locks down WinRM, and before sysprep runs.
# =============================================================================

Write-Output "=== Part 2: Backing up CIS policy state ==="

$scriptsPath = "C:\Windows\Setup\Scripts"
if (!(Test-Path $scriptsPath)) {
    New-Item -ItemType Directory -Force -Path $scriptsPath | Out-Null
}

# Layer 1: secedit (account policies, user rights, security options)
Write-Output "Exporting secedit policy..."
secedit.exe /export /cfg "$scriptsPath\cis-secpol.inf" /quiet

# Layer 2: auditpol (advanced audit subcategories)
Write-Output "Exporting audit policy..."
auditpol.exe /backup /file:"$scriptsPath\cis-auditpol.csv"

# Layer 3: Registry hives (section 18.x Administrative Template controls)
# secedit does NOT export HKLM\SOFTWARE\Policies — this is the critical layer
# that the original sysprep.ps1 was missing.
Write-Output "Exporting SOFTWARE\Policies\Microsoft registry hive..."
reg export "HKLM\SOFTWARE\Policies\Microsoft" "$scriptsPath\microsoft-policies.reg" /y

Write-Output "Exporting LSA registry hive..."
reg export "HKLM\SYSTEM\CurrentControlSet\Control\Lsa" "$scriptsPath\lsa-policies.reg" /y

# Write the RestoreCIS.ps1 script that runs on first boot after deployment
$restoreScript = "$scriptsPath\RestoreCIS.ps1"
@'
# Restore secedit security policy
secedit.exe /configure /db $env:windir\security\local.sdb /cfg C:\Windows\Setup\Scripts\cis-secpol.inf /overwrite /quiet

# Restore audit policy
auditpol.exe /restore /file:C:\Windows\Setup\Scripts\cis-auditpol.csv

# Restore SOFTWARE\Policies\Microsoft registry hive (all section 18.x controls)
if (Test-Path "C:\Windows\Setup\Scripts\microsoft-policies.reg") {
    reg import "C:\Windows\Setup\Scripts\microsoft-policies.reg"
}

# Restore LSA policy keys
if (Test-Path "C:\Windows\Setup\Scripts\lsa-policies.reg") {
    reg import "C:\Windows\Setup\Scripts\lsa-policies.reg"
}

# Self-destruct after successful restore
Unregister-ScheduledTask -TaskName 'RestoreCISPolicies' -Confirm:$false
'@ | Out-File -FilePath $restoreScript -Encoding ASCII -Force

# Register the first-boot scheduled task
$action    = New-ScheduledTaskAction -Execute 'powershell.exe' `
               -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File $restoreScript"
$trigger   = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" `
               -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName 'RestoreCISPolicies' `
    -Action $action -Trigger $trigger -Principal $principal -Force
Write-Output "RestoreCISPolicies scheduled task registered."

# =============================================================================
# PART 3: WinRM CIS controls
#
# These write AllowBasic=0 and related values. This LOCKS WinRM for any NEW
# connection attempts. The CURRENT session (this script) is unaffected —
# WinRM authentication only applies at connection time, not mid-session.
#
# This is why these must be in the same script as sysprep: after this block
# runs, no new WinRM connection can be established. Sysprep runs in Part 4
# within this same already-established session.
# =============================================================================

Write-Output "=== Part 3: WinRM CIS controls (locks WinRM for new connections) ==="

# CIS 18.10.88.1.1 — WinRM Client: Disable Basic authentication
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Client" "AllowBasic" 0

# CIS 18.10.88.1.2 — WinRM Client: Disable unencrypted traffic
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Client" "AllowUnencryptedTraffic" 0

# CIS 18.10.88.1.3 — WinRM Client: Disallow Digest authentication
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Client" "AllowDigest" 0

# CIS 18.10.88.2.1 — WinRM Service: Disable Basic authentication
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service" "AllowBasic" 0

# CIS 18.10.88.2.2 — WinRM Service: Disable remote management
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service" "AllowAutoConfig" 0

# CIS 18.10.88.2.3 — WinRM Service: Disable unencrypted traffic
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service" "AllowUnencryptedTraffic" 0

# CIS 18.10.88.2.4 — WinRM Service: Disallow RunAs credentials
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service" "DisableRunAs" 1

# CIS 18.10.89.1 — Disable Remote Shell Access
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service\WinRS" "AllowRemoteShellAccess" 0

Write-Output "WinRM is now locked. No new WinRM connections possible. Current session continues."

# =============================================================================
# PART 4: Sysprep
#
# Runs in the same session as Part 3. WinRM being locked does not affect
# this already-running PowerShell process.
# =============================================================================

Write-Output "=== Part 4: Sysprep ==="

# Lock down UAC network logon before generalize (CIS requirement for sysprep)
$uacPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
Set-ItemProperty -Path $uacPath -Name "LocalAccountTokenFilterPolicy" -Value 0 -Type DWord -Force

Write-Output "Running Sysprep..."
& $env:SystemRoot\System32\Sysprep\Sysprep.exe /oobe /generalize /quiet /quit /mode:vm

Write-Output "=== finalize.ps1 complete ==="
