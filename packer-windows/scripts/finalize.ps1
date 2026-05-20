# =============================================================================
# finalize.ps1 - Hardened Restoration
# =============================================================================

function Set-Reg {
    param($Path, $Name, $Value, $Type = 'DWord')
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
}

# Grant SYSTEM full control over registry keys locked by TrustedInstaller
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
Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" "RestrictReceivingNTLMTraffic" 2

# Backup CIS policy state
$scriptsPath = "C:\Windows\Setup\Scripts"
if (!(Test-Path $scriptsPath)) { New-Item -ItemType Directory -Force -Path $scriptsPath | Out-Null }

secedit.exe /export /cfg "$scriptsPath\cis-secpol.inf" /quiet
auditpol.exe /backup /file:"$scriptsPath\cis-auditpol.csv"

# Export hives
$hives = @(
    "HKLM\SOFTWARE\Policies", "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies",
    "HKLM\SYSTEM\CurrentControlSet\Control\Lsa", "HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters",
    "HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters", "HKLM\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters",
    "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
)
foreach ($hive in $hives) {
    $filename = ($hive -replace '\\', '_') + ".reg"
    reg export $hive "$scriptsPath\$filename" /y
}

# =============================================================================
# RestoreCIS.ps1 (The Boot-time engine)
# =============================================================================
$restoreScript = "$scriptsPath\RestoreCIS.ps1"
@'
Start-Transcript -Path "C:\Windows\Setup\Scripts\RestoreCIS.log"

# 1. Take ownership and restore keys
Grant-KeyAccess "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"

# 2. Merge Registry Hives
Get-ChildItem "C:\Windows\Setup\Scripts\*.reg" | ForEach-Object {
    Start-Process -FilePath "regedit.exe" -ArgumentList "/s $($_.FullName)" -Wait
}

# 3. Force-Apply Security Policies (Clear Sysprep interference)
secedit.exe /configure /db $env:windir\security\local.sdb /cfg C:\Windows\Setup\Scripts\cis-secpol.inf /overwrite /quiet
auditpol.exe /restore /file:C:\Windows\Setup\Scripts\cis-auditpol.csv

# 4. Enforce Policy Refresh
gpupdate /force /boot

# 5. Services
Start-Process -FilePath "C:\Windows\System32\OpenSSH\ssh-keygen.exe" -ArgumentList "-A" -NoNewWindow -Wait
Set-Service -Name sshd -StartupType Automatic
Start-Service -Name sshd

Unregister-ScheduledTask -TaskName 'RestoreCISPolicies' -Confirm:$false
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