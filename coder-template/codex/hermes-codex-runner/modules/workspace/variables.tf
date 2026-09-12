variable "namespace" {
  type = string
}
variable "runner_image" {
  type        = string
  description = "Immutable runner image reference including sha256 digest."
  validation {
    condition     = can(regex("@sha256:[0-9a-f]{64}$", var.runner_image))
    error_message = "runner_image must be pinned by sha256 digest."
  }
}
variable "storage_class_name" {
  type    = string
  default = ""
}
variable "image_pull_secret_name" {
  type        = string
  description = "Existing docker-registry Secret used to pull the private runner image."
  default     = "hermes-codex-runner-registry"
  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.image_pull_secret_name))
    error_message = "image_pull_secret_name must be a valid Kubernetes resource name."
  }
}
variable "coder_endpoint_cidrs" {
  type        = list(string)
  description = "Exact private Coder ingress CIDRs allowed only from the control agent."
  default     = []
  validation {
    condition     = alltrue([for cidr in var.coder_endpoint_cidrs : can(cidrhost(cidr, 0)) && !can(regex("/0$", cidr))])
    error_message = "coder_endpoint_cidrs must contain valid, non-default-route CIDRs."
  }
}
variable "gateway_namespace" {
  type    = string
  default = "services"
}
variable "gateway_pod_labels" {
  type    = map(string)
  default = { "app.kubernetes.io/controller" = "main", "hermes-profile" = "admin" }
}
