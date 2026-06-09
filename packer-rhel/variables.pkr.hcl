# --- AZURE CLOUD VARIABLES ---
# variable "subscription_id" {
  type    = string
  description = "The Azure Resource Group injected by GitHub"
}

# variable "resource_group" {
  type        = string
  description = "The Azure Resource Group injected by GitHub"
}

# variable "gallery_name" {
  type        = string
  description = "The Azure Compute Gallery injected by GitHub"
}

# variable "location" {
  type        = string
  description = "The Azure Region injected by GitHub"
}

# variable "vm_size" {
  type        = string
  description = "The size of the temporary build VM injected by GitHub"
  default     = "Standard_D2as_v7"
}

variable "image_version" {
  type        = string
  description = "The dynamic version of the image injected by GitHub Actions"
  default     = "1.0.0"
}

# --- HUAWEI CLOUD VARIABLES ---
variable "hw_access_key" {
  type    = string
  default = env("HW_ACCESS_KEY")
}

variable "hw_secret_key" {
  type    = string
  default = env("HW_SECRET_KEY")
}

variable "hw_project_id" {
  type    = string
  default = env("HW_PROJECT_ID")
}

variable "hw_region" {
  type    = string
  default = "my-kualalumpur-1" # Change to your target region
}

variable "hw_vpc_id" {
  type    = string
  default = env("HW_VPC_ID")
}

variable "hw_subnet_id" {
  type    = string
  default = env("HW_SUBNET_ID")
}

variable "hw_security_group_id" {
  type    = string
  default = env("HW_SECURITY_GROUP_ID")
}