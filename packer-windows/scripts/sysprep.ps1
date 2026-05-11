Write-Host "Applying UAC Network Logon Restrictions (Fixes windows-185)..."
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
if (!(Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
Set-ItemProperty -Path $regPath -Name "LocalAccountTokenFilterPolicy" -Value 0 -Type DWord -Force

Write-Host "CRITICAL FIX: Backing up CIS policies before Sysprep wipes them..."
$scriptsPath = "C:\Windows\Setup\Scripts"
if (!(Test-Path $scriptsPath)) { New-Item -ItemType Directory -Force -Path $scriptsPath | Out-Null }

secedit.exe /export /cfg "$scriptsPath\cis-secpol.inf" /quiet
auditpol.exe /backup /file:"$scriptsPath\cis-auditpol.csv"

Write-Host "Creating Azure-Proof Scheduled Task to automatically restore policies on first boot..."
$restoreScript = "$scriptsPath\RestoreCIS.ps1"
# We use single quotes (@') so PowerShell doesn't prematurely expand the variables during the build
$psCommand = @'
secedit.exe /configure /db $env:windir\security\local.sdb /cfg C:\Windows\Setup\Scripts\cis-secpol.inf /overwrite /quiet
auditpol.exe /restore /file:C:\Windows\Setup\Scripts\cis-auditpol.csv
Unregister-ScheduledTask -TaskName 'RestoreCISPolicies' -Confirm:$false
'@
Out-File -FilePath $restoreScript -InputObject $psCommand -Encoding ASCII -Force

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File $restoreScript"
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName 'RestoreCISPolicies' -Action $action -Trigger $trigger -Principal $principal

Write-Host "Running Sysprep to generalize the image..."
& $env:SystemRoot\System32\Sysprep\Sysprep.exe /oobe /generalize /quiet /quit /mode:vm
