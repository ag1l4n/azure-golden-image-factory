Write-Host "Applying UAC Network Logon Restrictions (Fixes windows-185)..."
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
if (!(Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
Set-ItemProperty -Path $regPath -Name "LocalAccountTokenFilterPolicy" -Value 0 -Type DWord -Force

Write-Host "CRITICAL FIX: Backing up CIS policies before Sysprep wipes them..."
$scriptsPath = "C:\Windows\Setup\Scripts"
if (!(Test-Path $scriptsPath)) { New-Item -ItemType Directory -Force -Path $scriptsPath | Out-Null }

# 1. Export the strict policies Ansible just applied
secedit.exe /export /cfg "$scriptsPath\cis-secpol.inf" /quiet
auditpol.exe /backup /file:"$scriptsPath\cis-auditpol.csv"

Write-Host "Creating SetupComplete.cmd to automatically restore policies on first boot..."
# 2. Windows natively runs SetupComplete.cmd as SYSTEM immediately after an image is deployed
$setupCmd = @"
@echo off
echo Restoring CIS Local Security Policy...
secedit.exe /configure /db %windir%\security\local.sdb /cfg C:\Windows\Setup\Scripts\cis-secpol.inf /overwrite /quiet
echo Restoring CIS Audit Policy...
auditpol.exe /restore /file:C:\Windows\Setup\Scripts\cis-auditpol.csv
"@
Out-File -FilePath "$scriptsPath\SetupComplete.cmd" -InputObject $setupCmd -Encoding ASCII -Force

Write-Host "Running Sysprep to generalize the image..."
& $env:SystemRoot\System32\Sysprep\Sysprep.exe /oobe /generalize /quiet /quit /mode:vm
