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

  image_publisher = "MicrosoftWindowsServer"   # ← fixed
  image_offer     = "WindowsServer"
  image_sku       = "2022-datacenter-azure-edition"

  build_resource_group_name = var.resource_group
  vm_size                   = var.vm_size

  communicator             = "ssh"
  ssh_username             = "packer"
  ssh_password             = var.ssh_password
  ssh_port                 = 22
  ssh_timeout              = "30m"
  pause_before_connecting  = "3m"              # ← added: wait for Windows to fully boot
  allowed_inbound_ip_addresses = ["0.0.0.0/0"]
  

  # custom_data is a SOURCE attribute — moved here from build block
  custom_data = base64encode(<<-EOF
    <powershell>
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction SilentlyContinue
    Start-Service sshd -ErrorAction SilentlyContinue
    Set-Service -Name sshd -StartupType Automatic
    $sshdConfig = 'C:\ProgramData\ssh\sshd_config'
    if (Test-Path $sshdConfig) {
      $content = Get-Content $sshdConfig
      $content = $content -replace '#PasswordAuthentication yes', 'PasswordAuthentication yes'
      $content = $content -replace 'PasswordAuthentication no', 'PasswordAuthentication yes'
      $content | Set-Content $sshdConfig
    } else {
      'PasswordAuthentication yes' | Out-File $sshdConfig -Encoding UTF8
    }
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -ErrorAction SilentlyContinue
    Restart-Service sshd -Force
    </powershell>
  EOF
  )

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

  provisioner "powershell" {
    inline = [
      "Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0",
      "Start-Service sshd",
      "Set-Service -Name sshd -StartupType Automatic",
      "New-NetFirewallRule -Name sshd -DisplayName 'OpenSSH Server' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -ErrorAction SilentlyContinue"
    ]
  }

  provisioner "powershell" {
    inline = [
      "$action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-ExecutionPolicy Bypass -Command \"Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0; Start-Service sshd; Set-Service -Name sshd -StartupType Automatic; Unregister-ScheduledTask -TaskName EnableOpenSSH -Confirm:$false\"'",
      "$trigger   = New-ScheduledTaskTrigger -AtStartup",
      "$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest",
      "Register-ScheduledTask -TaskName 'EnableOpenSSH' -Action $action -Trigger $trigger -Principal $principal -Force"
    ]
  }

  provisioner "powershell" {
    inline = [
      "& $env:SystemRoot\\System32\\Sysprep\\Sysprep.exe /oobe /generalize /quiet /quit",
      "while($true) { $imageState = (Get-ItemProperty HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Setup\\State).ImageState; if($imageState -ne 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') { Start-Sleep -s 10 } else { break } }"
    ]
  }
}
