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

source "azure-arm" "rocky-cis" {
  use_azure_cli_auth = true
  
  subscription_id           = var.subscription_id
  build_resource_group_name = var.resource_group
  
  # Rocky 9 Marketplace Image
  image_publisher = "resf"
  image_offer     = "rockylinux-x86_64"
  image_sku       = "9-base"
  image_version   = "latest"
  
  os_type         = "Linux"
  vm_size         = var.vm_size
  
  shared_image_gallery_destination {
    subscription          = var.subscription_id
    resource_group        = var.resource_group
    gallery_name          = var.gallery_name
    image_name            = "rocky-nvme-cis"
    image_version         = var.image_version
    replication_regions   = [var.location]
  }
}

build {
  sources = ["source.azure-arm.rocky-cis"]

  provisioner "ansible" {
    playbook_file = "../ansible/rhel-hardening-playbook.yml"
    user          = "packer"
    use_proxy     = false
    extra_arguments = [
      "--extra-vars", "ansible_python_interpreter=/usr/bin/python3"
    ]
  }
  provisioner "ansible" {
    playbook_file = "../ansible/rhel-remediations-l1-VM_adjusted.yml"
    user          = "packer"
    use_proxy     = false
    extra_arguments = [
      "--extra-vars", "ansible_python_interpreter=/usr/bin/python3"
    ]
  }
}
