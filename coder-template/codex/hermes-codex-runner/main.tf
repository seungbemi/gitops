module "workspace" {
  source             = "../modules/workspace"
  namespace          = var.namespace
  runner_image       = var.runner_image
  storage_class_name = var.storage_class_name
}

variable "namespace" {
  type = string
}

variable "runner_image" {
  type = string
}

variable "storage_class_name" {
  type    = string
  default = ""
}
