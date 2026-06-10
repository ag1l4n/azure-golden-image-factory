variable "hw_access_key" {
  type      = string
  sensitive = true
}

variable "hw_secret_key" {
  type      = string
  sensitive = true
}

variable "hw_project_id" {
  type      = string
  sensitive = true
}

variable "hw_region" {
  type    = string
  default = "my-kualalumpur-1" # Change to your target region
}

variable "hw_vpc_id" {
  type    = string
}

variable "hw_subnet_id" {
  type    = string
}

variable "hw_security_group_id" {
  type    = string
}