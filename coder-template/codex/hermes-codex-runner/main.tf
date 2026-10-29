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
  type        = string
  description = "Immutable Hermes Codex runner image reference."
  default     = "ghcr.io/seungbemi/hermes-codex-runner:sha-cc943784e7859fcc9f521febb988504ea446ce0d@sha256:c1dfb604394dc1ab75956bbae93dcec6c2f5ac84ee23a307913761790603634b"

  validation {
    condition     = can(regex("@sha256:[0-9a-f]{64}$", var.runner_image))
    error_message = "runner_image must be pinned by sha256 digest."
  }
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
