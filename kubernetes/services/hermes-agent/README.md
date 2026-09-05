# Hermes Agent

This reusable chart defines one Hermes security principal per Helm release. It
is instantiated independently as `hermes-admin` and `hermes-rina` in the
`services` namespace. Both releases are deliberately disabled until credentials,
environment configuration, and exact Telegram user IDs have been configured.

The chart uses the pinned `bjw-s/common` library for Deployments, Services,
PVCs, containers, and volume mounts. Hermes-specific ConfigMaps, RBAC,
NetworkPolicies, validation, knowledge-base policy, and alerts remain explicit
templates because they encode authorization policy rather than workload
boilerplate.

## Security boundaries

- Each release has a separate Deployment, PVC, ServiceAccount, Telegram bot,
  OpenRouter key, Kubernetes MCP sidecar, and optional browser.
- Kubernetes MCP runs in read-only mode and receives the projected Kubernetes
  token; the Hermes container does not mount that token.
- The admin ServiceAccount can observe selected cluster resources. It cannot
  read Secrets or pod logs and cannot exec, attach, port-forward, create tokens,
  or mutate resources.
- The Rina ServiceAccount is bound only in `rina-company` with an explicit
  resource list. It cannot observe another namespace.
- The built-in terminal, filesystem, code execution, browser/CDP, delegation,
  cron, skill installation, Kanban, and computer-use toolsets are disabled.
- Playwright is exposed through one exact read allowlist. Public navigation,
  snapshots, screenshots, console/network observation, waiting, and close are
  trusted reads. Clicks, typing, forms, dialogs, key presses, selects, tab
  mutation, code execution, file upload/download, PDF generation, routes, and
  raw storage manipulation are not registered. They stay unavailable until the
  exact-payload approval gateway is implemented.
- Wiki.js is the canonical human-readable knowledge store. Git-backed memory
  synchronization is intentionally absent. Local Hermes data contains sessions
  and rebuildable state only.
- The agent's security and behavior profile remains a read-only GitOps-owned
  `SOUL.md`; it is configuration, not user memory.

Vanilla Kubernetes NetworkPolicy cannot filter DNS names, inspect redirects, or
guarantee DNS-rebinding protection by itself. This chart blocks private IPv4
ranges at the packet layer and also blocks Gmail and Calendar web origins in
Playwright, but the origin option is only defense in depth. If the CNI does not
enforce `ipBlock.except` after DNAT, put browser egress through an authenticated,
DNS-aware proxy before enabling browsers.

The chart cannot classify every banking, commerce, password-manager, security,
or OAuth-grant site by hostname, and a click can initiate a download without a
malware scanner in this deployment. Keep browsers disabled until the egress
proxy and the credential/approval gateway enforce those hard denials. The
current browser manifests are an integration scaffold, not authorization to
activate unrestricted public browsing.

## Credential contract

Each enabled release uses the runtime Secret named by
`profile.runtimeSecretName`. The Hermes container reads only these keys through
explicit `secretKeyRef` entries:

- `OPENROUTER_API_KEY`
- `TELEGRAM_BOT_TOKEN`

The Telegram allowlist is supplied through a private Helm values source in
`gitops-secrets`; the public profile intentionally contains empty arrays. Group
access is always empty. Admin IDs must also be included in the allowlist.

Each release generates a `hermes-<profile>-environment` ConfigMap containing
`BROWSER_MCP_URL`. The chart also adds a narrowly scoped egress policy for the
exact Kubernetes API address instead of allowing an entire private service
range.

## Deferred integrations

The pinned GitHub MCP HTTP server expects a bearer token on each MCP request.
Putting that header in Hermes config would violate the requirement that Hermes
never receives GitHub credentials. Wiki.js has the same
process-level credential problem. These integrations therefore remain
fail-closed until a
separately built, audited credential gateway can:

1. hold each profile's token outside the Hermes and browser containers;
2. expose an exact read/write tool allowlist with correct MCP annotations;
3. bind staged payloads to bot, Telegram user, hash, expiry, and single use;
4. restrict Rina GitHub calls to the two approved repositories;
5. bind each Wiki.js API key to its permitted paths (`sebe` plus `shared` for
   admin; `rina` plus `shared` for Rina), and approval-gate every write; and
6. emit audit metrics without logging message bodies or credentials.

Wiki.js 2.5 requires broader page-management permission than a read-only API
client should need. The gateway must therefore normalize and enforce the path
allowlist independently on every query and mutation; Wiki.js permissions are a
second boundary, not the only boundary.

Do not enable `credentialGateway` merely by supplying an image name; add its
Deployment, tests, and restricted egress policy in the same reviewed change.

Google Workspace is intentionally out of scope for the initial deployment. No
Google OAuth client, refresh token, Gmail tool, or Calendar tool should be added
to either profile.

## Activation phases

1. **Base bot:** configure a separate OpenRouter key and Telegram bot token per
   profile, set exact numeric Telegram IDs, and enable Telegram plus the
   read-only Kubernetes MCP server. Wiki.js, GitHub, and browsers stay disabled.
2. **Knowledge:** deploy the reviewed policy gateway, mount the profile-specific
   Wiki.js token only into that gateway, then enable the knowledge-base MCP
   endpoint. Reads are automatic; writes are staged and require approval.
3. **Repositories:** add profile-specific fine-grained GitHub tokens to the
   gateway. The admin token is limited to explicitly selected personal private
   repositories; the Rina token is limited to the approved Rina source and
   GitOps repositories. Changes use branches and pull requests, never direct
   pushes to protected branches or merges.
4. **Browser:** enable read-only public browsing only after the DNS-aware egress
   proxy is in place. Interactive browser actions remain a separate reviewed
   capability.
