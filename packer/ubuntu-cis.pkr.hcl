packer {
  required_plugins {
    azure = {
      source  = "github.com/hashicorp/azure"
      version = "~> 2.0"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = "~> 1.0"
    }
  }
}

source "azure-arm" "ubuntu" {
  use_azure_cli_auth = true
  
  subscription_id                   = var.subscription_id
  build_resource_group_name         = var.resource_group
  
  os_type                           = "Linux"
  image_publisher                   = "Canonical"
  image_offer                       = "0001-com-ubuntu-server-jammy"
  image_sku                         = "22_04-lts-gen2"
  vm_size                           = "Standard_D2as_v7"
  
  shared_image_gallery_destination {
    subscription         = var.subscription_id
    resource_group       = var.resource_group
    gallery_name         = var.gallery_name
    image_name           = "ubuntu-nvme-cis"
    image_version        = var.image_version
    replication_regions  = [var.location]
  }
}

build {
  sources = ["source.azure-arm.ubuntu"]

  provisioner "ansible" {
    playbook_file = "../ansible/hardening-playbook.yml"
    user          = "packer"
    use_proxy     = false
    ansible_env_vars = [
      "ANSIBLE_ROLES_PATH=../ansible/roles",
      "ANSIBLE_ALLOW_BROKEN_CONDITIONALS=true"
    ]
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E sh '{{ .Path }}'"
    inline = [
      "/usr/sbin/waagent -force -deprovision+user && export HISTSIZE=0 && sync"
    ]
    inline_shebang = "/bin/sh -x"
  }
}
