module "workspace" {
  source                 = "./modules/workspace"
  namespace              = var.namespace
  runner_image           = var.runner_image
  nfs_server             = var.nfs_server
  nfs_path_template      = var.nfs_path_template
  kubernetes_api_cidr    = var.kubernetes_api_cidr
  image_pull_secret_name = var.image_pull_secret_name
  coder_endpoint_cidrs   = var.coder_endpoint_cidrs
}

variable "namespace" {
  type = string
}

variable "runner_image" {
  type = string
}

variable "nfs_server" {
  type        = string
  description = "NFS server used for retained Codex and job state."
  default     = "diskstation.local"
}

variable "nfs_path_template" {
  type        = string
  description = "Dedicated NFS path containing one {workspace} placeholder."
  default     = "/volume1/LTS/coder/caffeine/.hermes-codex-runner/{workspace}"
}

variable "kubernetes_api_cidr" {
  type        = string
  description = "Kubernetes API service address used by the read-only runner identity."
  default     = "10.96.0.1/32"
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
