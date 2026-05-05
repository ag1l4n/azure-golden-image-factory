Write-Output "Bypassing Chocolatey: Downloading official OpenSCAP MSI natively..."

# Pointing to a stable release that we know has the win32.msi asset attached
$MsiUrl = "https://github.com/OpenSCAP/openscap/releases/download/1.3.6/OpenSCAP-1.3.6-win32.msi"
$MsiPath = "C:\openscap.msi"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 1. Download OpenSCAP MSI
Invoke-WebRequest -Uri $MsiUrl -OutFile $MsiPath

Write-Output "Installing OpenSCAP silently..."
# 2. Execute Windows Installer quietly with no restart
Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$MsiPath`" /qn /norestart" -Wait -NoNewWindow

# 3. Locate the installed executable (Usually installs to x86 on 64-bit systems)
$OscapExe = "C:\Program Files (x86)\OpenSCAP\oscap.exe"
if (-Not (Test-Path $OscapExe)) {
    $OscapExe = "C:\Program Files\OpenSCAP\oscap.exe"
}

Write-Output "Downloading SCAP Security Guide..."
# 4. Download and extract the SCAP policies
Invoke-WebRequest -Uri 'https://github.com/ComplianceAsCode/content/releases/download/v0.1.74/scap-security-guide-0.1.74.zip' -OutFile 'C:\ssg.zip'
Expand-Archive -Path 'C:\ssg.zip' -DestinationPath 'C:\ssg' -Force

# 5. Prepare the reporting directory
New-Item -Path "C:\CIS-Reports" -ItemType Directory -Force | Out-Null
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$ReportPath = "C:\CIS-Reports\compliance-report-$Timestamp.html"

Write-Output "Executing OpenSCAP evaluation..."
# 6. Run the native scan
& $OscapExe xccdf eval `
  --profile xccdf_org.ssgproject.content_profile_cis_level1_memberserver `
  --report $ReportPath `
  'C:\ssg\scap-security-guide-0.1.74\ssg-windows_server_2022-ds.xml'

Write-Output "Scan complete. Report saved to $ReportPath"
