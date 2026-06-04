# =============================================================================
# finalize.ps1 - Corrected Registry Access & Restoration
# =============================================================================

function Set-Reg {
    param($Path, $Name, $Value, $Type = 'DWord')
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
}

# This function is used by the parent finalize script
function Grant-KeyAccess {
    param($Path)
    if (Test-Path $Path) {
        $acl = Get-Acl $Path
        $permission = "NT AUTHORITY\SYSTEM","FullControl","Allow"
        $accessRule = New-Object System.Security.AccessControl.RegistryAccessRule($permission)
        $acl.SetAccessRule($accessRule)
        Set-Acl $Path $acl
    }
}

Write-Output "=== Part 1: Initial Hardening ==="
Unregister-ScheduledTask -TaskName 'RestoreCISPolicies' -Confirm:$false -ErrorAction SilentlyContinue
Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" "RestrictReceivingNTLMTraffic" 2

$scriptsPath = "C:\Windows\Setup\Scripts"
if (!(Test-Path $scriptsPath)) { 
    New-Item -ItemType Directory -Force -Path $scriptsPath | Out-Null 
}

# =============================================================================
# RestoreCIS.ps1 (The Boot-time engine)
# =============================================================================
$restoreScript = "$scriptsPath\RestoreCIS.ps1"
@'
Start-Transcript -Path "C:\Windows\Setup\Scripts\RestoreCIS.log"

# RE-DEFINED: The function must exist inside the boot script process
function Grant-KeyAccess {
    param($Path)
    if (Test-Path $Path) {
        $acl = Get-Acl $Path
        $permission = "NT AUTHORITY\SYSTEM","FullControl","Allow"
        $accessRule = New-Object System.Security.AccessControl.RegistryAccessRule($permission)
        $acl.SetAccessRule($accessRule)
        Set-Acl $Path $acl
    }
}

Unregister-ScheduledTask -TaskName 'RestoreCISPolicies' -Confirm:$false -ErrorAction SilentlyContinue

# INTEGRATED: Grant permissions so we can overwrite Policies
$sysPolicy = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
Grant-KeyAccess $sysPolicy

# 1. Apply Security Policy
secedit.exe /configure /db $env:windir\security\local.sdb /cfg C:\Windows\Setup\Scripts\CIS-Gold-State.inf /overwrite /quiet

# 2. Apply Audit Policy
auditpol.exe /restore /file:C:\Windows\Setup\Scripts\CIS-Auditpol.csv

# 3. Enforce Registry State
regedit.exe /s C:\Windows\Setup\Scripts\CIS-Policies.reg

# 4. Enforce Policy Refresh
gpupdate /force /boot
if ($LASTEXITCODE -ne 0) { Write-Error "gpupdate failed!" }

# =====================================================================
# THE FIX: REPAIR SYSPREP OPENSSH CORRUPTION
# =====================================================================
Write-Output "Purging corrupted Sysprep SSH keys..."
Remove-Item -Path "$env:ProgramData\ssh\ssh_host_*" -Force -Recurse -ErrorAction SilentlyContinue

Write-Output "Generating fresh SSH Host Keys..."
Start-Process -FilePath "C:\Windows\System32\OpenSSH\ssh-keygen.exe" -ArgumentList "-A" -NoNewWindow -Wait

$aclScript = "C:\Windows\System32\OpenSSH\FixHostFilePermissions.ps1"
if (Test-Path $aclScript) {
    & powershell.exe -ExecutionPolicy Bypass -File $aclScript -Confirm:$false
}

Write-Output "Starting OpenSSH Server..."
Set-Service -Name sshd -StartupType Automatic
Start-Service -Name sshd

# Punch through the CIS Firewall Lockdown
$profiles = @("DomainProfile", "PrivateProfile", "PublicProfile")
foreach ($prof in $profiles) {
    $path = "HKLM:\SOFTWARE\Policies\Microsoft\WindowsFirewall\$prof"
    if (Test-Path $path) { 
        Set-ItemProperty -Path $path -Name "AllowLocalPolicyMerge" -Value 1 -Force 
    }
}

Remove-NetFirewallRule -Name "Allow-SSH-Pipeline" -ErrorAction SilentlyContinue
New-NetFirewallRule -Name "Allow-SSH-Pipeline" -DisplayName "Allow SSH Pipeline" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -Profile Any

Stop-Transcript
'@ | Out-File -FilePath $restoreScript -Encoding ASCII -Force

# Register Task
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-ExecutionPolicy Bypass -File $restoreScript"
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName 'RestoreCISPolicies' -Action $action -Trigger $trigger -Principal $principal -Force

# Finalize WinRM
Write-Output "=== Part 3: WinRM Lockdown ==="
$winrmPaths = @("HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Client", "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service")
foreach ($path in $winrmPaths) {
    Set-Reg $path "AllowBasic" 0
    Set-Reg $path "AllowUnencryptedTraffic" 0
}

# Sysprep
Start-Process -FilePath "$env:SystemRoot\System32\Sysprep\Sysprep.exe" -ArgumentList "/oobe /generalize /quiet /quit /mode:vm" -Wait
