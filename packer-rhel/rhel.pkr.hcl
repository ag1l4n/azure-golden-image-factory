packer {
  required_plugins {
    azure = {
      version = ">= 2.0.0"
      source  = "github.com/hashicorp/azure"
    }
    huaweicloud = {
      version = ">= 1.2.0"
      source  = "github.com/huaweicloud/huaweicloud"
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
  vm_size         = var.vm_size
  
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

source "huaweicloud-ecs" "rhel_cis" {
  access_key         = var.hw_access_key
  secret_key         = var.hw_secret_key
  project_id         = var.hw_project_id
  region             = var.hw_region
  
  image_name         = "rhel9-cis-v${var.image_version}"
  source_image_name  = "Red Hat Enterprise Linux 9.0 64bit" 
  flavor             = "s6.large.2" 
  
  vpc_id             = var.hw_vpc_id
  subnets            = [var.hw_subnet_id]
  security_groups    = [var.hw_security_group_id]
  
  eip_bandwidth_size = 5
  eip_type           = "5_bgp"
  ssh_username       = "root"
}

build {
  sources = [
#    "source.azure-arm.rhel-cis"
    "source.huaweicloud-ecs.rhel_cis"
    ]

  provisioner "ansible" {
    only = ["azure-arm.rhel-cis"]
    playbook_file = "../ansible/rhel-hardening-playbook.yml"
    user          = "packer"
    use_proxy     = false
    extra_arguments = [
      "--extra-vars", "ansible_python_interpreter=/usr/bin/python3"
    ]
  }

  provisioner "ansible" {
    only = ["huaweicloud-ecs.rhel_cis"]
    playbook_file   = "../ansible/rhel-hardening-playbook.yml"
    user            = "root"
    extra_arguments = [
      "--extra-vars", "cloud_platform=huawei",
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
  provisioner "shell" {
    only = ["azure-arm.rhel-cis"]
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E sh '{{ .Path }}'"
    inline = [
      "/usr/sbin/waagent -force -deprovision+user && export HISTSIZE=0 && sync"
    ]
    inline_shebang = "/bin/sh -x"
  }

  provisioner "shell" {
    only = ["huaweicloud-ecs.rhel_cis"]
    inline = ["cloud-init clean && export HISTSIZE=0 && sync"]
  }
}
