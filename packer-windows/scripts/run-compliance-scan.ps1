Write-Output "Preparing pre-baked CIS compliance scan..."
Set-ExecutionPolicy Bypass -Scope Process -Force
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

New-Item -Path "C:\CIS-Reports" -ItemType Directory -Force | Out-Null

Write-Output "Installing OpenSCAP via Chocolatey..."
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
choco install openscap -y --no-progress

Write-Output "Downloading SCAP Security Guide..."
Invoke-WebRequest -Uri 'https://github.com/ComplianceAsCode/content/releases/download/v0.1.74/scap-security-guide-0.1.74.zip' -OutFile 'C:\ssg.zip'
Expand-Archive -Path 'C:\ssg.zip' -DestinationPath 'C:\ssg' -Force

$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$ReportPath = "C:\CIS-Reports\compliance-report-$Timestamp.html"

Write-Output "Executing OpenSCAP evaluation..."
& 'C:\Program Files\OpenSCAP\oscap.exe' xccdf eval `
  --profile xccdf_org.ssgproject.content_profile_cis_level1_memberserver `
  --report $ReportPath `
  'C:\ssg\scap-security-guide-0.1.74\ssg-windows_server_2022-ds.xml'

Write-Output "Scan complete. Report saved to $ReportPath"
