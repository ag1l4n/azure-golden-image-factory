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

  # 1. Install OpenSSH FIRST (While the system is still unhardened and friendly)
  provisioner "powershell" {
    inline = [
      "Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0",
      "Set-Service -Name sshd -StartupType Automatic",
      "New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -ErrorAction SilentlyContinue"
    ]
  }

  # 2. Scheduled Task: Sysprep strips SSH host keys. This ensures SSH starts and generates keys on first boot, then deletes itself.
  provisioner "powershell" {
    inline = [
      "$action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-ExecutionPolicy Bypass -Command \"Start-Service sshd; Unregister-ScheduledTask -TaskName EnableOpenSSH -Confirm:$false\"'",
      "$trigger   = New-ScheduledTaskTrigger -AtStartup",
      "$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest",
      "Register-ScheduledTask -TaskName 'EnableOpenSSH' -Action $action -Trigger $trigger -Principal $principal -Force"
    ]
  }

  # 3. Create Trusted Path and Upload Scripts LAST
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

  # 4. Execute Hardening and Sysprep in ONE breath
  provisioner "powershell" {
    elevated_user     = var.local_admin_username
    elevated_password = var.local_admin_password
    
    environment_vars = [
      "LOCAL_ADMIN_USERNAME=${var.local_admin_username}",
      "LOCAL_ADMIN_PASSWORD=${var.local_admin_password}"
    ]
    
    valid_exit_codes = [0, 1]
    
    inline = [
      # Force Execution Policy Bypass for this specific process so CIS doesn't lock it
      "Set-ExecutionPolicy Bypass -Scope Process -Force",
      
      # Unblock the files downloaded via network
      "Unblock-File -Path 'C:\\Windows\\PackerBuild\\cis-harden.ps1' -ErrorAction SilentlyContinue",
      "Unblock-File -Path 'C:\\Windows\\PackerBuild\\wrapper.ps1' -ErrorAction SilentlyContinue",
      
      # Execute the wrapper from the trusted path
      "& 'C:\\Windows\\PackerBuild\\wrapper.ps1'"
    ]
  }
}
