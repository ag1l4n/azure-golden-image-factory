variable "subscription_id" {
  type    = string
  description = "The Azure Resource Group injected by GitHub"
}

variable "resource_group" {
  type        = string
  description = "The Azure Resource Group injected by GitHub"
}

variable "gallery_name" {
  type        = string
  description = "The Azure Compute Gallery injected by GitHub"
}

variable "location" {
  type        = string
  description = "The Azure Region injected by GitHub"
}

variable "vm_size" {
  type        = string
  description = "The size of the temporary build VM injected by GitHub"
  default     = "Standard_D2as_v7"
}

variable "image_version" {
  type        = string
  description = "The dynamic version of the image injected by GitHub Actions"
  default     = "1.0.0"
}

variable "client_id" {
  type      = string
  sensitive = true
}

variable "client_secret" {
  type      = string
  sensitive = true
}

variable "local_admin_username" {
  type    = string
  default = "sysadmin"  # match what your pipeline uses
}

variable "local_admin_password" {
  type      = string
  sensitive = true
}

variable "winrm_password" {
  type      = string
  sensitive = true
}
