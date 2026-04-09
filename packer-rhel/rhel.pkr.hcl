packer {
  required_plugins {
    azure = {
      version = ">= 2.0.0"
      source  = "github.com/hashicorp/azure"
    }
    ansible = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

source "azure-arm" "rhel-cis" {
  use_azure_cli_auth = true
  
  subscription_id           = var.subscription_id
  build_resource_group_name = var.resource_group
  
  # RHEL 9 Marketplace Image
  image_publisher = "RedHat"
  image_offer     = "RHEL"
  image_sku       = "9-lvm-gen2"
  
  os_type         = "Linux"
  vm_size         = "Standard_D2as_v7"
  
  shared_image_gallery_destination {
    subscription          = var.subscription_id
    resource_group        = var.resource_group
    gallery_name          = var.gallery_name
    image_name            = "rhel-nvme-cis"
    image_version         = var.image_version
    replication_regions   = [var.location]
  }
  
  managed_image_name                = "packer-rhel-9-cis-tmp"
  managed_image_resource_group_name = var.resource_group
}

build {
  sources = ["source.azure-arm.rhel-cis"]

  provisioner "ansible" {
    playbook_file = "../ansible/rhel-hardening-playbook.yml"
    user          = "packer"
    use_proxy     = false
    extra_arguments = [
      "--extra-vars", "ansible_python_interpreter=/usr/bin/python3"
    ]
  }
}
