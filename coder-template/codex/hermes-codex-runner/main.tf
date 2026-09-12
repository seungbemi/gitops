module "workspace" {
  source                 = "./modules/workspace"
  namespace              = var.namespace
  runner_image           = var.runner_image
  storage_class_name     = var.storage_class_name
  image_pull_secret_name = var.image_pull_secret_name
  coder_endpoint_cidrs   = var.coder_endpoint_cidrs
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

variable "image_pull_secret_name" {
  type        = string
  description = "Existing docker-registry Secret used to pull the private runner image."
  default     = "hermes-codex-runner-registry"
}

variable "coder_endpoint_cidrs" {
  type        = list(string)
  description = "Exact private Coder ingress CIDRs allowed only from the control agent."
  default     = []
}
