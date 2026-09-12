terraform {
  required_providers {
    coder      = { source = "coder/coder", version = "~> 2.13" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.38" }
  }
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU cores"
  type         = "number"
  default      = 4
  mutable      = true
  validation {
    min = 2
    max = 8
  }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory (GiB)"
  type         = "number"
  default      = 8
  mutable      = true
  validation {
    min = 4
    max = 16
  }
}

data "coder_parameter" "disk" {
  name         = "disk"
  display_name = "Persistent disk (GiB)"
  type         = "number"
  default      = 20
  mutable      = false
  validation {
    min = 10
    max = 100
  }
}

locals {
  # Workspace names are stable before first creation, allowing the encrypted
  # runner Secret and gateway trust bundle to be provisioned without putting
  # credentials in Terraform state.
  name = "hermes-codex-runner-${data.coder_workspace.me.name}"
  labels = {
    "app.kubernetes.io/name"     = "codex-runner"
    "app.kubernetes.io/instance" = local.name
    "app.kubernetes.io/part-of"  = "hermes-delegation"
    "hermes.codex/workspace-id"  = data.coder_workspace.me.id
  }
  agent_labels = {
    "app.kubernetes.io/name"     = "codex-control-agent"
    "app.kubernetes.io/instance" = local.name
    "app.kubernetes.io/part-of"  = "hermes-delegation"
    "hermes.codex/workspace-id"  = data.coder_workspace.me.id
  }
}

resource "coder_agent" "main" {
  os   = "linux"
  arch = "amd64"
  metadata {
    display_name = "CPU"
    key          = "cpu"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }
  metadata {
    display_name = "Memory"
    key          = "memory"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }
}

resource "kubernetes_persistent_volume_claim_v1" "state" {
  metadata {
    name      = local.name
    namespace = var.namespace
    labels    = local.labels
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = var.storage_class_name == "" ? null : var.storage_class_name
    resources { requests = { storage = "${data.coder_parameter.disk.value}Gi" } }
  }
  lifecycle { prevent_destroy = true }
}

resource "kubernetes_deployment_v1" "agent" {
  count = data.coder_workspace.me.start_count
  metadata {
    name      = "${local.name}-agent"
    namespace = var.namespace
    labels    = local.agent_labels
  }
  spec {
    replicas = 1
    selector { match_labels = local.agent_labels }
    template {
      metadata {
        labels      = local.agent_labels
        annotations = { "container.apparmor.security.beta.kubernetes.io/coder-agent" = "runtime/default" }
      }
      spec {
        automount_service_account_token = false
        enable_service_links            = false
        security_context {
          run_as_non_root = true
          run_as_user     = 10000
          run_as_group    = 10000
          fs_group        = 10000
          seccomp_profile { type = "RuntimeDefault" }
        }
        container {
          name              = "coder-agent"
          image             = var.runner_image
          image_pull_policy = "IfNotPresent"
          command           = ["/bin/bash", "-c"]
          args              = [coder_agent.main.init_script]
          env {
            name  = "CODER_AGENT_TOKEN"
            value = coder_agent.main.token
          }
          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities { drop = ["ALL"] }
          }
          resources {
            requests = { cpu = "50m", memory = "64Mi" }
            limits   = { cpu = "250m", memory = "256Mi" }
          }
          volume_mount {
            name       = "home"
            mount_path = "/home/coder"
          }
          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }
        }
        volume {
          name = "home"
          empty_dir {}
        }
        volume {
          name = "tmp"
          empty_dir {}
        }
      }
    }
  }
}

resource "kubernetes_deployment_v1" "runner" {
  count = data.coder_workspace.me.start_count
  metadata {
    name      = local.name
    namespace = var.namespace
    labels    = local.labels
  }
  spec {
    replicas = 1
    strategy { type = "Recreate" }
    selector { match_labels = local.labels }
    template {
      metadata {
        labels      = local.labels
        annotations = { "container.apparmor.security.beta.kubernetes.io/runner" = "runtime/default" }
      }
      spec {
        automount_service_account_token = false
        enable_service_links            = false
        security_context {
          run_as_non_root = true
          run_as_user     = 10000
          run_as_group    = 10000
          fs_group        = 10000
          seccomp_profile { type = "RuntimeDefault" }
        }
        init_container {
          name    = "prepare-state"
          image   = var.runner_image
          command = ["/bin/sh", "-c"]
          args    = ["install -d -o 10000 -g 10000 -m 0700 /state/home /state/runner-state /state/jobs"]
          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            run_as_non_root            = false
            run_as_user                = 0
            capabilities {
              drop = ["ALL"]
              add  = ["CHOWN", "DAC_OVERRIDE"]
            }
          }
          volume_mount {
            name       = "state"
            mount_path = "/state"
          }
        }
        container {
          name              = "runner"
          image             = var.runner_image
          image_pull_policy = "IfNotPresent"
          command           = ["/hermes-codex-runner"]
          env {
            name  = "RUNNER_STATE_ROOT"
            value = "/runner-state"
          }
          env {
            name  = "RUNNER_WORKSPACE_ROOT"
            value = "/workspace/jobs"
          }
          env {
            name  = "RUNNER_TLS_CERT_FILE"
            value = "/runner-credentials/tls.crt"
          }
          env {
            name  = "RUNNER_TLS_KEY_FILE"
            value = "/runner-credentials/tls.key"
          }
          env {
            name = "RUNNER_BEARER_TOKEN"
            value_from {
              secret_key_ref {
                name = local.name
                key  = "bearer-token"
              }
            }
          }
          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities { drop = ["ALL"] }
          }
          resources {
            requests = { cpu = "500m", memory = "1Gi" }
            limits   = { cpu = tostring(data.coder_parameter.cpu.value), memory = "${data.coder_parameter.memory.value}Gi" }
          }
          port {
            name           = "https"
            container_port = 8443
          }
          readiness_probe {
            http_get {
              path   = "/livez"
              port   = "https"
              scheme = "HTTPS"
            }
          }
          liveness_probe {
            http_get {
              path   = "/livez"
              port   = "https"
              scheme = "HTTPS"
            }
          }
          volume_mount {
            name       = "state"
            mount_path = "/home/coder"
            sub_path   = "home"
          }
          volume_mount {
            name       = "state"
            mount_path = "/runner-state"
            sub_path   = "runner-state"
          }
          volume_mount {
            name       = "state"
            mount_path = "/workspace/jobs"
            sub_path   = "jobs"
          }
          volume_mount {
            name       = "runner-tmp"
            mount_path = "/tmp"
          }
          volume_mount {
            name       = "credentials"
            mount_path = "/runner-credentials"
            read_only  = true
          }
        }
        volume {
          name = "state"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.state.metadata[0].name
          }
        }
        volume {
          name = "runner-tmp"
          empty_dir {}
        }
        volume {
          name = "credentials"
          secret {
            secret_name = local.name
            # Secret volumes are root-owned. fsGroup 10000 plus group-read is
            # required for the non-root runner to read its TLS key.
            default_mode = "0440"
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "runner" {
  metadata {
    name      = local.name
    namespace = var.namespace
    labels    = local.labels
  }
  spec {
    selector = local.labels
    port {
      name        = "https"
      port        = 443
      target_port = "https"
    }
  }
}

resource "kubernetes_network_policy_v1" "runner" {
  metadata {
    name      = local.name
    namespace = var.namespace
  }
  spec {
    pod_selector { match_labels = local.labels }
    policy_types = ["Ingress", "Egress"]
    ingress {
      from {
        namespace_selector { match_labels = { "kubernetes.io/metadata.name" = var.gateway_namespace } }
        pod_selector { match_labels = var.gateway_pod_labels }
      }
      ports {
        protocol = "TCP"
        port     = "8443"
      }
    }
    egress {
      to {
        namespace_selector { match_labels = { "kubernetes.io/metadata.name" = "kube-system" } }
        pod_selector { match_labels = { "k8s-app" = "kube-dns" } }
      }
      ports {
        protocol = "UDP"
        port     = "53"
      }
      ports {
        protocol = "TCP"
        port     = "53"
      }
    }
    egress {
      to {
        ip_block {
          cidr   = "0.0.0.0/0"
          except = ["10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8", "169.254.0.0/16", "172.16.0.0/12", "192.168.0.0/16", "224.0.0.0/4"]
        }
      }
      ports {
        protocol = "TCP"
        port     = "443"
      }
    }
  }
}

resource "kubernetes_network_policy_v1" "agent" {
  metadata {
    name      = "${local.name}-agent"
    namespace = var.namespace
  }
  spec {
    pod_selector { match_labels = local.agent_labels }
    policy_types = ["Ingress", "Egress"]
    egress {
      to {
        namespace_selector { match_labels = { "kubernetes.io/metadata.name" = "kube-system" } }
        pod_selector { match_labels = { "k8s-app" = "kube-dns" } }
      }
      ports {
        protocol = "UDP"
        port     = 53
      }
      ports {
        protocol = "TCP"
        port     = 53
      }
    }
    egress {
      to {
        namespace_selector { match_labels = { "kubernetes.io/metadata.name" = var.namespace } }
        pod_selector { match_labels = { "app.kubernetes.io/name" = "coder" } }
      }
      ports {
        protocol = "TCP"
        port     = 8080
      }
      ports {
        protocol = "TCP"
        port     = 443
      }
    }
    egress {
      to {
        ip_block {
          cidr   = "0.0.0.0/0"
          except = ["10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8", "169.254.0.0/16", "172.16.0.0/12", "192.168.0.0/16", "224.0.0.0/4"]
        }
      }
      ports {
        protocol = "TCP"
        port     = 443
      }
    }
  }
}
