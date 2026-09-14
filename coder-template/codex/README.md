# Isolated Hermes Codex runner template

This replaces neither `../kube.tf` nor any existing human workspace. It is a
single agent-only template backed by one module and intentionally has no NFS,
Home Assistant PVC, Frigate PVC, Kubernetes credential, or service-account
token mount.

Before a workspace starts, provision an encrypted Secret named
`hermes-codex-runner-<workspace-name>` in the Coder namespace with `bearer-token`,
`tls.crt`, and `tls.key`. The certificate must cover the matching service DNS
name. The Secret is referenced, never created or read, by Terraform, keeping
its contents out of template state. The gateway receives only the corresponding
bearer token and CA certificate, plus a Coder session token used by its trusted
lifecycle client. The runner image input must use an immutable `@sha256:` digest.
Provision the separate `hermes-codex-runner-registry` docker-registry Secret so
the namespace can pull that private image; Terraform references only its name.

The module mounts a dedicated per-workspace NFS path and uses distinct
subdirectories for the Codex home, runner control state, and job files. The
path must exist on the NFS server, be owned by UID/GID 10000, and be derived
from a template containing exactly one `{workspace}` placeholder. Only the
runner Pod sees this mount; never point it at a human Coder home or shared
repository root. The Coder control agent runs in a separate Deployment with
an ephemeral home and no runner credentials, authentication, or job mounts.
Its NetworkPolicy permits the Coder control-plane connection without granting
that private route to the runner Pod. This preserves login and threads across
stops while keeping the interactive Coder surface and production configuration
out of the runner.

When Coder's access URL resolves privately, pass its exact ingress address in
`coder_endpoint_cidrs`. That exception applies only to the ephemeral control
agent, never to the Codex runner.

Default-deny NetworkPolicy permits ingress only from the admin Hermes gateway,
DNS, and public HTTPS excluding private, loopback, link-local, carrier-grade
NAT, multicast, and cluster ranges. Validate the CNI's post-DNAT behavior before
production because Kubernetes NetworkPolicy cannot express DNS names.

The runner container uses unconfined Kubernetes seccomp and AppArmor profiles
because Codex's Linux filesystem sandbox uses bubblewrap user namespaces. The
container remains non-root, drops every Linux capability, forbids privilege
escalation, and uses a read-only root filesystem. Its dedicated service account
has cluster-wide read-only status access (including pod logs) and no Secret or
mutation permissions. The control agent and init container retain the
runtime-default profiles and do not receive that service-account token.

The base runner image includes Codex, Node.js, Git, GitHub CLI, curl, jq,
Python 3, and ripgrep. Additional exact CLI artifacts are installed into the
persistent NFS-backed tool directory only after Hermes records approval of the
name, version, official HTTPS URL, SHA-256, archive format, and executable path.
The exact artifact remains available across workspace rebuilds; upgrades or
different sources require a new approval.

The local module is nested inside `hermes-codex-runner/`, making that directory
a self-contained upload archive. Point `coder templates push --directory`
directly at it.

The gateway creates a missing named workspace from this template, starts it
before dispatch, and configures a one-day Coder TTL. It deliberately does not
stop the workspace after each job; Coder stops it when that TTL expires. Coder
remains the source of truth for workspace build state.

Coder workspace deletion does not delete the NFS directory. Completed artifact
retention and final storage deletion therefore require an explicit gateway
cleanup workflow after the 30-day retention window.

After the first workspace start, authenticate once inside the runner container
with `codex login --device-auth`. This writes subscription authentication only
to the retained Codex home; it does not pass through Terraform, Kubernetes
Secrets, gateway payloads, or Telegram.
