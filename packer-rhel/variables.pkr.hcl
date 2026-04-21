variable "subscription_id" {
  type    = string
  default = "8f1d7ab7-0a79-4a10-a744-b36a4f8f4123"
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
