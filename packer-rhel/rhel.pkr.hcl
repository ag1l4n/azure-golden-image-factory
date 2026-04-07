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
  
  # THE FIX: Tell Packer where to put the temporary build VM
  build_resource_group_name = "rg-hardening-pipeline"
  
  # RHEL 9 Marketplace Image
  image_publisher = "RedHat"
  image_offer     = "RHEL"
  image_sku       = "9-lvm-gen2"
  
  os_type         = "Linux"
  vm_size         = "Standard_D2s_v3"
  
  shared_image_gallery_destination {
    resource_group        = "rg-hardening-pipeline"
    gallery_name          = "hardenedimageswblsec"
    image_name            = "rhel-9-cis-l1"
    image_version         = "1.0.0"
    replication_regions   = ["southeastasia"]
  }
  
  managed_image_name                = "packer-rhel-9-cis-tmp"
  managed_image_resource_group_name = "rg-hardening-pipeline"
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
