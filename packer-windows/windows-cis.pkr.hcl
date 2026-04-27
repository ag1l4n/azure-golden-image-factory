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

  # Base image — Windows Server 2022 Datacenter
  image_publisher = "MicrosoftWindowsServer"
  image_offer     = "WindowsServer"
  image_sku       = "2022-datacenter-g2"

  # Build VM config
  build_resource_group_name = var.resource_group
  # location        = var.location
  vm_size         = var.vm_size
  

  # Use WinRM to communicate during the build
  communicator   = "winrm"
  winrm_username = "packer"
  winrm_password = var.winrm_password
  winrm_use_ssl  = true
  winrm_insecure = true
  winrm_timeout  = "10m"

  os_type = "Windows"

  # Destination in Shared Image Gallery
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

  # Step 1: Run your CIS hardening PowerShell script
  provisioner "file" {
    source      = "./scripts/cis-harden.ps1"
    destination = "C:\\Windows\\Temp\\cis-harden.ps1"
  }

  provisioner "file" {
    source      = "./scripts/wrapper.ps1"
    destination = "C:\\Windows\\Temp\\wrapper.ps1"
  }

  provisioner "powershell" {
    elevated_user    = "packer"
    elevated_password = var.winrm_password
    environment_vars = [
      "LOCAL_ADMIN_USERNAME=${var.local_admin_username}",
      "LOCAL_ADMIN_PASSWORD=${var.local_admin_password}"
    ]
    valid_exit_codes = [0, 1, 267014]
    inline = [
      # Write env vars to a file the scheduled task can read
      # (Scheduled tasks don't inherit environment variables)
      "$env:LOCAL_ADMIN_USERNAME | Out-File C:\\Windows\\Temp\\cis-username.txt -Encoding UTF8 -NoNewline",
      "$env:LOCAL_ADMIN_PASSWORD | Out-File C:\\Windows\\Temp\\cis-password.txt -Encoding UTF8 -NoNewline",

      # Remove any previous completion/failure markers
      "Remove-Item C:\\Windows\\Temp\\cis-complete.txt -Force -ErrorAction SilentlyContinue",
      "Remove-Item C:\\Windows\\Temp\\cis-failed.txt   -Force -ErrorAction SilentlyContinue",

      # Register the task to run wrapper.ps1 as SYSTEM
      "$action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-ExecutionPolicy Bypass -NonInteractive -File C:\\Windows\\Temp\\wrapper.ps1'",
      "$trigger   = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(5)",
      "$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest",
      "$settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 30)",
      "Register-ScheduledTask -TaskName 'CIS-Harden' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force",

      # Start it immediately
      "Start-ScheduledTask -TaskName 'CIS-Harden'",
      "Write-Host 'CIS hardening task started. Polling for completion...'",

      # Poll for completion marker — wrapper.ps1 writes this when done
      "$timeout  = 1800  # 30 minutes",
      "$elapsed  = 0",
      "$interval = 15",
      "do {",
      "    Start-Sleep -Seconds $interval",
      "    $elapsed += $interval",
      "    $state = (Get-ScheduledTask -TaskName 'CIS-Harden').State",
      "    Write-Host \"[$elapsed`s] Task state: $state\"",
      "    if (Test-Path 'C:\\Windows\\Temp\\cis-failed.txt') { Write-Host 'CIS hardening reported failure.'; break }",
      "    if ($elapsed -ge $timeout) { Write-Host 'Timeout waiting for CIS hardening.'; break }",
      "} while (-not (Test-Path 'C:\\Windows\\Temp\\cis-complete.txt'))",

      "if (Test-Path 'C:\\Windows\\Temp\\cis-complete.txt') { Write-Host 'CIS hardening completed successfully.' }",

      # Cleanup
      "Unregister-ScheduledTask -TaskName 'CIS-Harden' -Confirm:$false -ErrorAction SilentlyContinue",
      "Remove-Item C:\\Windows\\Temp\\cis-username.txt -Force -ErrorAction SilentlyContinue",
      "Remove-Item C:\\Windows\\Temp\\cis-password.txt -Force -ErrorAction SilentlyContinue"
    ]
  }

  # 3. Restart to apply hardening
  provisioner "windows-restart" {
    restart_timeout       = "15m"
    restart_check_command = "powershell -command \"& {Write-Output 'restarted'}\""
    pause_before          = "30s"
  }

  # 4. OpenSSH
  provisioner "powershell" {
    elevated_user     = "packer"
    elevated_password = var.winrm_password
    inline = [
      "Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0",
      "Start-Service sshd",
      "Set-Service -Name sshd -StartupType Automatic",
      "New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -ErrorAction SilentlyContinue"
    ]
  }

  # 5. First-boot task for OpenSSH after Sysprep
  provisioner "powershell" {
    elevated_user     = "packer"
    elevated_password = var.winrm_password
    inline = [
      "$action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-ExecutionPolicy Bypass -Command \"Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0; Start-Service sshd; Set-Service -Name sshd -StartupType Automatic; Unregister-ScheduledTask -TaskName EnableOpenSSH -Confirm:$false\"'",
      "$trigger   = New-ScheduledTaskTrigger -AtStartup",
      "$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest",
      "Register-ScheduledTask -TaskName 'EnableOpenSSH' -Action $action -Trigger $trigger -Principal $principal -Force"
    ]
  }

  # 6. Sysprep
  provisioner "powershell" {
    elevated_user     = "packer"
    elevated_password = var.winrm_password
    inline = [
      "& $env:SystemRoot\\System32\\Sysprep\\Sysprep.exe /oobe /generalize /quiet /quit",
      "while($true) { $imageState = (Get-ItemProperty HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Setup\\State).ImageState; if($imageState -ne 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') { Start-Sleep -s 10 } else { break } }"
    ]
  }
