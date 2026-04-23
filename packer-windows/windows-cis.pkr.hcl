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
  provisioner "powershell" {
    script = "./scripts/cis-harden.ps1"
  }

  # Step 2: Restart to apply hardening (GPO, services, etc.)
  provisioner "windows-restart" {
    restart_timeout = "15m"
  }

  # Step 3: Enable OpenSSH for the scan phase after build
  provisioner "powershell" {
    inline = [
      "Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0",
      "Start-Service sshd",
      "Set-Service -Name sshd -StartupType Automatic",
      "New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22"
    ]
  }

  # Step 4: Generalize (sysprep) — required for Azure gallery images
  provisioner "powershell" {
    inline = [
      "& $env:SystemRoot\\System32\\Sysprep\\Sysprep.exe /oobe /generalize /quiet /quit",
      "while($true) { $imageState = Get-ItemProperty HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Setup\\State | Select ImageState; if($imageState.ImageState -ne 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') { Write-Output $imageState.ImageState; Start-Sleep -s 10 } else { break } }"
    ]
  }
}
