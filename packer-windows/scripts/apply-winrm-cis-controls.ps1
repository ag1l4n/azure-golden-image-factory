# =============================================================================
# apply-winrm-cis-controls.ps1
#
# Applies all CIS WinRM controls that were skipped during the Ansible pass
# (--skip-tags winrm_connectivity). These must be written to the GROUP POLICY
# registry paths, not the WSMan: provider, because Cinc Auditor reads the
# registry. The WSMan: provider path is NOT what the scanner checks.
#
# Also restores RestrictReceivingNTLMTraffic which the Ansible post_task
# set to 0 to keep the Packer session alive.
# =============================================================================

function Set-Reg {
    param($Path, $Name, $Value, $Type = 'DWord')
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
    Write-Output "SET: $Path\$Name = $Value"
}

Write-Output "=== Applying WinRM CIS controls via registry policy paths ==="

# ── CIS 18.10.88.1.1 — WinRM Client: Disable Basic authentication
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Client" "AllowBasic" 0

# ── CIS 18.10.88.1.2 — WinRM Client: Disable unencrypted traffic
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Client" "AllowUnencryptedTraffic" 0

# ── CIS 18.10.88.1.3 — WinRM Client: Disallow Digest authentication
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Client" "AllowDigest" 0

# ── CIS 18.10.88.2.1 — WinRM Service: Disable Basic authentication
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service" "AllowBasic" 0

# ── CIS 18.10.88.2.2 — WinRM Service: Disable remote management
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service" "AllowAutoConfig" 0

# ── CIS 18.10.88.2.3 — WinRM Service: Disable unencrypted traffic
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service" "AllowUnencryptedTraffic" 0

# ── CIS 18.10.88.2.4 — WinRM Service: Disallow RunAs credentials
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service" "DisableRunAs" 1

# ── CIS 18.10.89.1 — Disable Remote Shell Access
Set-Reg "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service\WinRS" "AllowRemoteShellAccess" 0

Write-Output "=== Restoring NTLM restriction undone by Ansible post_task ==="

# ── CIS 2.3.11.11 — RestrictReceivingNTLMTraffic
# The Ansible post_task set this to 0 to keep Packer's session alive.
# Now that Packer is done with WinRM, restore the CIS-required value of 2.
Set-Reg "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\MSV1_0" "RestrictReceivingNTLMTraffic" 2

Write-Output "=== Installing OpenSSH Server for pipeline SCP access ==="
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'
New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' `
    -DisplayName 'OpenSSH Server (sshd)' `
    -Enabled True -Direction Inbound -Protocol TCP `
    -Action Allow -LocalPort 22 -ErrorAction SilentlyContinue

Write-Output "=== apply-winrm-cis-controls.ps1 complete ==="
