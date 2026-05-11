Write-Host "Applying UAC Network Logon Restrictions (Fixes windows-185)..."
# Applied here at the absolute end so Packer doesn't get locked out!
$regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
if (!(Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }

Set-ItemProperty -Path $regPath -Name "LocalAccountTokenFilterPolicy" -Value 0 -Type DWord -Force
Write-Output "Running Sysprep to generalize the image..."
& $env:SystemRoot\System32\Sysprep\Sysprep.exe /oobe /generalize /quiet /quit
