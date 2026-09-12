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
variable "gateway_namespace" {
  type    = string
  default = "services"
}
variable "gateway_pod_labels" {
  type    = map(string)
  default = { "app.kubernetes.io/controller" = "main", "hermes-profile" = "admin" }
}
