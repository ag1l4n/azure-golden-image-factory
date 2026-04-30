# ./packer-windows/windows-cis.pkr.hcl

packer {
  required_plugins {
    azure = {
      source  = "github.com/hashicorp/azure"
      version = "~> 2"
    }
  }
}

source "azure-arm" "windows" {
  subscription_id = var.subscription_id
  client_id       = var.client_id
  client_secret   = var.client_secret

  # Switch back to g2 — WinRM works correctly on this SKU
  image_publisher = "MicrosoftWindowsServer"
  image_offer     = "WindowsServer"
  image_sku       = "2022-datacenter-g2"    # ← changed back

  build_resource_group_name = var.resource_group
  vm_size                   = var.vm_size

  communicator   = "winrm"
  winrm_username = "packer"
  winrm_password = var.ssh_password
  winrm_use_ssl  = true
  winrm_insecure = true
  winrm_timeout  = "15m"

  os_type = "Windows"

  shared_image_gallery_destination {
    resource_group      = var.resource_group
    gallery_name        = var.gallery_name
    image_name          = "windows-server-2022-cis"
    image_version       = var.image_version
    replication_regions = [var.location]
  }
}

build {
  sources = ["source.azure-arm.windows"]

  # --- STEP 1: Upload scripts ---
  provisioner "file" {
    source      = "./scripts/cis-harden.ps1"
    destination = "C:\\Windows\\Temp\\cis-harden.ps1"
  }

  provisioner "file" {
    source      = "./scripts/wrapper.ps1"
    destination = "C:\\Windows\\Temp\\wrapper.ps1"
  }

  # --- STEP 2: Run CIS hardening as SYSTEM scheduled task ---
  # The WinRM session stays completely idle during hardening.
  # The CIS script runs in an isolated SYSTEM process — WinRM
  # auth is never touched by secedit or security policy changes.
  provisioner "powershell" {
    elevated_user     = "packer"
    elevated_password = var.ssh_password
    valid_exit_codes  = [0, 267014]
    inline = [
      # Write credentials to temp files so the SYSTEM task can read them
      # (Scheduled tasks don't inherit the WinRM session's environment)
      "[System.IO.File]::WriteAllText('C:\\Windows\\Temp\\u.txt', '${var.local_admin_username}')",
      "[System.IO.File]::WriteAllText('C:\\Windows\\Temp\\p.txt', '${var.local_admin_password}')",

      # Remove any stale completion/failure markers from previous runs
      "Remove-Item 'C:\\Windows\\Temp\\done.txt'   -Force -ErrorAction SilentlyContinue",
      "Remove-Item 'C:\\Windows\\Temp\\failed.txt'  -Force -ErrorAction SilentlyContinue",

      # Register the wrapper as a SYSTEM scheduled task
      "$a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-ExecutionPolicy Bypass -NonInteractive -WindowStyle Hidden -File C:\\Windows\\Temp\\wrapper.ps1'",
      "$t = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(5)",
      "$p = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest",
      "$s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 60) -MultipleInstances IgnoreNew",
      "Register-ScheduledTask -TaskName 'CIS-Harden' -Action $a -Trigger $t -Principal $p -Settings $s -Force | Out-Null",

      # Trigger immediately
      "Start-ScheduledTask -TaskName 'CIS-Harden'",
      "Write-Host 'CIS hardening task started. Polling for completion...'",

      # Poll every 20s for up to 30 minutes (90 attempts)
      "$i = 0",
      "do {",
      "    Start-Sleep -Seconds 20",
      "    $i++",
      "    $state = (Get-ScheduledTask -TaskName 'CIS-Harden' -ErrorAction SilentlyContinue).State",
      "    Write-Host \"[$($i * 20)s] Task state: $state\"",
      "    if (Test-Path 'C:\\Windows\\Temp\\failed.txt') {",
      "        $msg = Get-Content 'C:\\Windows\\Temp\\failed.txt' -Raw",
      "        Write-Host \"CIS hardening reported failure: $msg\"",
      "        break",
      "    }",
      "} until ((Test-Path 'C:\\Windows\\Temp\\done.txt') -or $i -ge 90)",

      # Report outcome
      "if (Test-Path 'C:\\Windows\\Temp\\done.txt') {",
      "    Write-Host 'CIS hardening completed successfully.'",
      "} else {",
      "    Write-Host 'WARNING: CIS hardening did not complete within 30 minutes.'",
      "}",

      # Cleanup
      "Unregister-ScheduledTask -TaskName 'CIS-Harden' -Confirm:$false -ErrorAction SilentlyContinue",
      "Remove-Item 'C:\\Windows\\Temp\\u.txt'      -Force -ErrorAction SilentlyContinue",
      "Remove-Item 'C:\\Windows\\Temp\\p.txt'      -Force -ErrorAction SilentlyContinue",
      "Remove-Item 'C:\\Windows\\Temp\\done.txt'   -Force -ErrorAction SilentlyContinue",
      "Remove-Item 'C:\\Windows\\Temp\\failed.txt'  -Force -ErrorAction SilentlyContinue"
    ]
  }

  # --- STEP 3: Restart to apply hardening ---
  provisioner "windows-restart" {
    restart_timeout       = "20m"
    pause_before          = "30s"
    restart_check_command = "powershell -command \"& {Write-Output 'restarted'}\""
  }

  # --- STEP 4: Enable OpenSSH for scan phase ---
  provisioner "powershell" {
    elevated_user     = "packer"
    elevated_password = var.ssh_password
    inline = [
      "Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction SilentlyContinue",
      "Start-Service sshd",
      "Set-Service -Name sshd -StartupType Automatic",
      "New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -ErrorAction SilentlyContinue",

      # Enable password auth in sshd_config for scan phase
      "$cfg = 'C:\\ProgramData\\ssh\\sshd_config'",
      "if (Test-Path $cfg) {",
      "    $c = Get-Content $cfg",
      "    $c = $c -replace '#PasswordAuthentication yes','PasswordAuthentication yes'",
      "    $c = $c -replace 'PasswordAuthentication no','PasswordAuthentication yes'",
      "    $c | Set-Content $cfg",
      "}",
      "Restart-Service sshd -Force"
    ]
  }

  # --- STEP 5: Register first-boot task to re-enable OpenSSH after Sysprep ---
  # Sysprep resets service states — this task re-enables SSH on first boot
  # of any VM provisioned from the golden image
  provisioner "powershell" {
    elevated_user     = "packer"
    elevated_password = var.ssh_password
    inline = [
      "$a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-ExecutionPolicy Bypass -Command \"Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0; Start-Service sshd; Set-Service -Name sshd -StartupType Automatic; Unregister-ScheduledTask -TaskName EnableOpenSSH -Confirm:$false\"'",
      "$t = New-ScheduledTaskTrigger -AtStartup",
      "$p = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest",
      "Register-ScheduledTask -TaskName 'EnableOpenSSH' -Action $a -Trigger $t -Principal $p -Force | Out-Null",
      "Write-Host 'OpenSSH first-boot task registered.'"
    ]
  }

  # --- STEP 6: Sysprep ---
  # Must be last — generalizes the image for Azure gallery distribution
  provisioner "powershell" {
    elevated_user     = "packer"
    elevated_password = var.ssh_password
    inline = [
      "& $env:SystemRoot\\System32\\Sysprep\\Sysprep.exe /oobe /generalize /quiet /quit",
      "while($true) {",
      "    $imageState = (Get-ItemProperty 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Setup\\State').ImageState",
      "    Write-Host \"Sysprep state: $imageState\"",
      "    if ($imageState -eq 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') { break }",
      "    Start-Sleep -Seconds 10",
      "}"
    ]
  }
}
