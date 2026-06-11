packer {
  required_plugins {
    huaweicloud = {
      version = ">= 0.8.0"
      source  = "github.com/huaweicloud/huaweicloud"
    }
    ansible = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/ansible"
    }
  }
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

  ssh_username       = "root"
}

build {
  sources = [
    "source.huaweicloud-ecs.rhel_cis"
    ]

  provisioner "ansible" {
    playbook_file   = "../ansible/rhel-hardening-playbook.yml"
    user            = "root"
    use_proxy       = false
    extra_arguments = [
      "--extra-vars", "cloud_platform=huawei",
      "--extra-vars", "ansible_python_interpreter=/usr/bin/python3"
    ]
  }

  provisioner "ansible" {
    playbook_file = "../ansible/rhel-remediations-l1-VM_adjusted.yml"
    user          = "root"
    use_proxy     = false
    extra_arguments = [
      "--extra-vars", "ansible_python_interpreter=/usr/bin/python3"
    ]
  }

  provisioner "shell" {
    inline = [
      "sudo cloud-init clean --logs",
      "sudo truncate -s 0 /etc/machine-id",
      "sudo rm -f /var/lib/dbus/machine-id",
      "sudo ln -s /etc/machine-id /var/lib/dbus/machine-id",
      "sudo rm -f /root/.ssh/authorized_keys",
      "sudo rm -f /home/*/.ssh/authorized_keys",
      "cat /dev/null > ~/.bash_history && history -c",
      "sync"
    ]
  }

  post-processor "manifest" {
    output     = "${path.root}/manifest.json"
    strip_path = true
    custom_data = {
      image_version = var.image_version
      cis_level     = "L1"
      cloud         = "huawei"
    }
  }
}
