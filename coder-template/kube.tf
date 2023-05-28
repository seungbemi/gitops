terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 0.6.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.12.1"
    }
  }
}

provider "coder" {
  feature_use_managed_variables = "true"
}

data "coder_parameter" "use_kubeconfig" {
  name        = "use_kubeconfig"
  type        = "bool"
  description = <<-EOF
  Use host kubeconfig? (true/false)
  Set this to false if the Coder host is itself running as a Pod on the same
  Kubernetes cluster as you are deploying workspaces to.
  Set this to true if the Coder host is running outside the Kubernetes cluster
  for workspaces.  A valid "~/.kube/config" must be present on the Coder host.
  EOF
  mutable     = true
}

data "coder_parameter" "namespace" {
  name        = "namespace"
  type        = "string"
  description = "The Kubernetes namespace to create workspaces in (must exist prior to creating workspaces)"
  mutable     = true
}

data "coder_parameter" "cpu" {
  name        = "CPU cores"
  type        = "number"
  description = "Number of CPU cores"
  mutable     = true
  default     = 2
}

data "coder_parameter" "memory" {
  name        = "memory"
  type        = "number"
  description = "Memory (__ GB)"
  mutable     = true
  default     = 2
}

provider "kubernetes" {
  # Authenticate via ~/.kube/config or a Coder-specific ServiceAccount, depending on admin preferences
  config_path = data.coder_parameter.use_kubeconfig == true ? "~/.kube/config" : null
}

data "coder_workspace" "me" {}

resource "coder_agent" "main" {
  os   = "linux"
  arch = "amd64"

  login_before_ready     = false
  startup_script_timeout = 180
  startup_script         = <<-EOT
    set -e
    # install and start code-server
    curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/tmp/code-server --version 4.13.0
    /tmp/code-server/bin/code-server --auth none --port 13337 >/tmp/code-server.log 2>&1 &
  EOT
}

# code-server
resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "code-server"
  icon         = "/icon/code.svg"
  url          = "http://localhost:13337?folder=/home/coder"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 3
    threshold = 10
  }
}

resource "kubernetes_pod" "main" {
  count = data.coder_workspace.me.start_count
  metadata {
    name      = "coder-${lower(data.coder_workspace.me.owner)}-${lower(data.coder_workspace.me.name)}"
    namespace = "${data.coder_parameter.namespace.value}"
    labels = {
      "app.kubernetes.io/name"     = "coder-workspace"
      "app.kubernetes.io/instance" = "coder-workspace-${lower(data.coder_workspace.me.owner)}-${lower(data.coder_workspace.me.name)}"
      "app.kubernetes.io/part-of"  = "coder"
      // Coder specific labels.
      "com.coder.resource"       = "true"
      "com.coder.workspace.id"   = data.coder_workspace.me.id
      "com.coder.workspace.name" = data.coder_workspace.me.name
      "com.coder.user.id"        = data.coder_workspace.me.owner_id
      "com.coder.user.username"  = data.coder_workspace.me.owner
    }
    annotations = {
      "com.coder.user.email" = data.coder_workspace.me.owner_email
    }
  }
  spec {
    security_context {
      run_as_user = "1000"
      fs_group    = "1000"
    }
    container {
      name              = "dev"
      image             = "codercom/enterprise-base:ubuntu"
      image_pull_policy = "Always"
      command           = ["sh", "-c", coder_agent.main.init_script]
      security_context {
        run_as_user = "1000"
      }
      env {
        name  = "CODER_AGENT_TOKEN"
        value = coder_agent.main.token
      }
      resources {
        requests = {
          "cpu"    = "250m"
          "memory" = "512Mi"
        }
        limits = {
          "cpu"    = "${data.coder_parameter.cpu.value}"
          "memory" = "${data.coder_parameter.memory.value}Gi"
        }
      }
      volume_mount {
        mount_path = "/home/coder"
        sub_path   = "${lower(data.coder_workspace.me.name)}"
        name       = "home"
        read_only  = false
      }
    }

    volume {
      name = "home"
      nfs {
        server = "diskstation.local"
        path = "/volume1/LTS/coder"
      }
    }


    affinity {
      pod_anti_affinity {
        // This affinity attempts to spread out all workspace pods evenly across
        // nodes.
        preferred_during_scheduling_ignored_during_execution {
          weight = 1
          pod_affinity_term {
            topology_key = "kubernetes.io/hostname"
            label_selector {
              match_expressions {
                key      = "app.kubernetes.io/name"
                operator = "In"
                values   = ["coder-workspace"]
              }
            }
          }
        }
      }
    }
  }
}
