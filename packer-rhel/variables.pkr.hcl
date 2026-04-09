variable "subscription_id" {
  type    = string
  default = "8f1d7ab7-0a79-4a10-a744-b36a4f8f4123"
}

variable "resource_group" {
  type    = string
  default = "rg-hardening-pipeline"
}

variable "location" {
  type    = string
  default = "southcentralus"
}

variable "gallery_name" {
  type    = string
  default = "galhardening"
}

variable "image_version" {
  type        = string
  description = "The dynamic version of the image injected by GitHub Actions"
  default     = "1.0.0"
}
