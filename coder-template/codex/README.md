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

The module gives each workspace one retained PVC and mounts distinct subpaths
for the Codex home, runner control state, and job files. Only the runner Pod
sees those mounts. The Coder control agent runs in a separate Deployment with
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

The local module is nested inside `hermes-codex-runner/`, making that directory
a self-contained upload archive. Point `coder templates push --directory`
directly at it.

The gateway creates a missing named workspace from this template, starts it
before dispatch, and configures a one-day Coder TTL. It deliberately does not
stop the workspace after each job; Coder stops it when that TTL expires. Coder
remains the source of truth for workspace build state.

`prevent_destroy` protects unfinished workspace storage. Completed artifact
retention and final workspace deletion therefore require an explicit gateway
cleanup workflow after the 30-day retention window; stopping a workspace does
not delete its PVC.

After the first workspace start, authenticate once inside the runner container
with `codex login --device-auth`. This writes subscription authentication only
to the retained Codex home; it does not pass through Terraform, Kubernetes
Secrets, gateway payloads, or Telegram.
