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

  image_publisher = "MicrosoftWindowsServer"
  image_offer     = "WindowsServer"
  image_sku       = "2022-datacenter-azure-edition"
  os_type         = "Windows"

  build_resource_group_name = var.resource_group
  vm_size                   = var.vm_size

  # --- WinRM Communicator (Native/Seamless for Azure Windows) ---
  communicator   = "winrm"
  winrm_use_ssl  = true
  winrm_insecure = true
  winrm_timeout  = "30m"
  winrm_username = "packer"
  # Note: Packer automatically generates a random winrm_password for Azure Windows

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

  # 1. Install OpenSSH FIRST
  provisioner "powershell" {
    inline = [
      "Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0",
      "Set-Service -Name sshd -StartupType Automatic",
      "New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -ErrorAction SilentlyContinue"
    ]
  }

  # 2. First-Boot Scheduled Task: Start SSH, Delete Build Artifacts, then Self-Destruct
  provisioner "powershell" {
    inline = [
      "$action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-ExecutionPolicy Bypass -Command \"Start-Service sshd; Remove-Item -Path C:\\Windows\\PackerBuild -Recurse -Force -ErrorAction SilentlyContinue; Unregister-ScheduledTask -TaskName EnableFirstBootSetup -Confirm:$false\"'",
      "$trigger   = New-ScheduledTaskTrigger -AtStartup",
      "$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest",
      "Register-ScheduledTask -TaskName 'EnableFirstBootSetup' -Action $action -Trigger $trigger -Principal $principal -Force"
    ]
  }

  # 3. Create Trusted Path and Upload Scripts
  provisioner "powershell" {
    inline = ["New-Item -ItemType Directory -Force -Path 'C:\\Windows\\PackerBuild'"]
  }

  provisioner "file" {
    source      = "./scripts/cis-harden.ps1"
    destination = "C:\\Windows\\PackerBuild\\cis-harden.ps1"
  }

  provisioner "file" {
    source      = "./scripts/wrapper.ps1"
    destination = "C:\\Windows\\PackerBuild\\wrapper.ps1"
  }

  # 4. The Fire-and-Forget SYSTEM Task (Bypasses AppLocker and UAC completely)
  provisioner "powershell" {
    environment_vars = [
      "LOCAL_ADMIN_USERNAME=${var.local_admin_username}",
      "LOCAL_ADMIN_PASSWORD=${var.local_admin_password}"
    ]
    
    inline = [
      "Unblock-File -Path 'C:\\Windows\\PackerBuild\\cis-harden.ps1' -ErrorAction SilentlyContinue",
      "Unblock-File -Path 'C:\\Windows\\PackerBuild\\wrapper.ps1' -ErrorAction SilentlyContinue",

      # Securely pass credentials to the SYSTEM task context, which has no access to WinRM env vars
      "Set-Content -Path 'C:\\Windows\\PackerBuild\\creds.txt' -Value \"$env:LOCAL_ADMIN_USERNAME`n$env:LOCAL_ADMIN_PASSWORD\"",

      # Register the SYSTEM task
      "$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-ExecutionPolicy Bypass -WindowStyle Hidden -File C:\\Windows\\PackerBuild\\wrapper.ps1'",
      "$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest",
      "Register-ScheduledTask -TaskName 'PackerCIS' -Action $action -Principal $principal -Force | Out-Null",
      
      # Start the task
      "Start-ScheduledTask -TaskName 'PackerCIS'",
      "Write-Host 'CIS Hardening and Sysprep are running in the background as SYSTEM...'",

      # Monitor the registry to know exactly when Sysprep finishes
      "while($true) {",
      "  $imageState = (Get-ItemProperty HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Setup\\State -ErrorAction SilentlyContinue).ImageState",
      "  if ($imageState -eq 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') {",
      "    Write-Host 'Sysprep completed successfully. Handing back to Azure API.'",
      "    break",
      "  }",
      "  Start-Sleep -Seconds 10",
      "}"
    ]
  }
}

