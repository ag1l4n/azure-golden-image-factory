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
  tenant_id       = var.tenant_id 
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

  provisioner "file" {
    source      = "./scripts/cis-harden.ps1"
    destination = "C:\\Windows\\Temp\\cis-harden.ps1"
  }

  provisioner "file" {
    source      = "./scripts/wrapper.ps1"
    destination = "C:\\Windows\\Temp\\wrapper.ps1"
  }

  provisioner "powershell" {
    environment_vars = [
      "LOCAL_ADMIN_USERNAME=${var.local_admin_username}",
      "LOCAL_ADMIN_PASSWORD=${var.local_admin_password}"
    ]
    valid_exit_codes = [0, 1]
    inline = [
      "& 'C:\\Windows\\Temp\\wrapper.ps1'"
    ]
  }

  provisioner "windows-restart" {
    restart_timeout       = "20m"
    pause_before          = "30s"
    restart_check_command = "powershell -command \"& {Write-Output 'restarted'}\""
  }

  # Install OpenSSH for the final image
  provisioner "powershell" {
    inline = [
      "Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0",
      "Set-Service -Name sshd -StartupType Automatic",
      "New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -ErrorAction SilentlyContinue"
    ]
  }

  # Scheduled Task: Sysprep strips SSH host keys. This ensures SSH starts and generates keys on first boot, then deletes itself.
  provisioner "powershell" {
    inline = [
      "$action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-ExecutionPolicy Bypass -Command \"Start-Service sshd; Unregister-ScheduledTask -TaskName EnableOpenSSH -Confirm:$false\"'",
      "$trigger   = New-ScheduledTaskTrigger -AtStartup",
      "$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest",
      "Register-ScheduledTask -TaskName 'EnableOpenSSH' -Action $action -Trigger $trigger -Principal $principal -Force"
    ]
  }

  # Standard Azure Windows Sysprep Loop
  provisioner "powershell" {
    inline = [
      "& $env:SystemRoot\\System32\\Sysprep\\Sysprep.exe /oobe /generalize /quiet /quit",
      "while($true) { $imageState = (Get-ItemProperty HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Setup\\State).ImageState; if($imageState -ne 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') { Start-Sleep -s 10 } else { break } }"
    ]
  }
}
