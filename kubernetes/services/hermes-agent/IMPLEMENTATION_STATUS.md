# Hermes usable-product implementation status

Last reviewed: 2026-10-24

This file records evidence and phase gates. A local implementation, a merged
change, a healthy rollout, and a passed reliability gate are different states;
do not mark a phase complete by inferring one from another.

## Current live baseline

- Argo CD reports `hermes-admin` synced and healthy in `services`; the live
  Deployment is fully ready with no container restarts.
- The live Hermes gateway and dashboard run pinned release `v0.22.5`. The
  dashboard reports config schema 51, requires authentication, cannot update
  GitOps-owned configuration, and now probes the sibling gateway through its
  loopback health listener instead of falsely reporting it as stopped.
- Telegram connected successfully after one bounded DNS fallback attempt. A
  direct `getMe` check succeeded for the configured bot, but delivery has not
  yet been measured for the seven-day P0 reliability window.
- The policy gateway reports PostgreSQL, Wiki.js, Home Assistant, and Paperless
  healthy. The Coder credential and runner bearer are under encrypted GitOps
  ownership. The active Coder token expires at 2026-11-23T12:16:40Z, is bounded
  to 30 days, and has only `user:read`, `organization:read`, `template:read`,
  and `workspace:*`. The superseded unrestricted token and a rejected scoped
  candidate were expired after the replacement passed live permission checks.
- The `sebe/hermes` Coder workspace is healthy and currently runs runner digest
  `sha256:3188d113316a63d027c6d31c36110bee6cb933df7fa88d8c7efd303064bd6f2d`.
  Runner API version 1, protocol version 0.154.0, and Codex subscription login
  all passed live capability checks. A bounded, read-only analysis job
  (`job_E_08m82WX-_4XvONN_M9jiZF`) completed through the full gateway, Coder,
  runner, and Codex path without an execution error.
- After the coordinated Coder token, runner bearer, approval HMAC, and database
  password rotation, a second bounded analysis job
  (`job_nKKxdWwGPWf4xgGgl8IXU6h3`) completed successfully. Live Secret values
  matched their encrypted source, PostgreSQL accepted the replacement role
  password, all gateway dependencies were healthy, and runner capabilities
  again reported Codex healthy with protocol version 0.154.0.
- The dashboard is protected by an Authentik public OIDC client using
  authorization code plus S256 PKCE, a strict callback URI, and the Sebe-only
  `Hermes Admins` application policy. Discovery, JWKS, unauthenticated redirect,
  and an existing-session browser login all passed. Hermes reports only the
  `self-hosted` provider, `auth_required: true`, and a healthy running gateway.

## Deployed foundation

### GitOps chart

- Hermes is pinned consistently to `v0.22.5` and immutable multi-architecture
  digest `sha256:9c5561579f3ffdf333401797094ac3a743738d6c25d40f4331c7bf77b694238d`.
- An init check compares `hermes --version` with `Chart.appVersion` and blocks
  a mismatched rollout.
- Configuration schema version 51 is explicit and the removed
  `cron.model_drift_guard` key is no longer rendered.
- The dashboard is labelled as an administration observer; GitOps-owned
  `config.yaml` and `SOUL.md` are mounted read-only.
- Authentik OIDC issuer, public client ID, and scopes are GitOps-owned. No
  browser-client secret is created or stored.
- Alerts cover Coder `needs_login`, prolonged quota waits, and token expiry.
  Prometheus loaded and evaluated the expiry rule as healthy and inactive.

### Policy gateway and runner

- Implementation jobs resolve their starting revision to an exact GitHub
  commit before an expiring durable preview is shown. No implementation job is
  inserted until the authorized Telegram callback consumes that exact contract.
- The preview records objective, acceptance criteria, repository, paths,
  operations, execution budget, and backend/model/reasoning policy. Broad `*`
  scope is explicitly warned and replay cannot create a duplicate job.
- Coder, runner protocol, and Codex login preflights are classified as
  authentication, quota, transient, or permanent failures.
- Authentication failures pause the affected job in `needs_login`; quota and
  transient failures use bounded backoff without replaying an unknown attempt.
- Telegram notifications and loopback endpoints provide durable status, retry,
  and cancellation controls.
- `codex_get_job` now returns the latest durable Codex result, so a refreshed
  status view shows the actual outcome instead of only a terminal state.
- Runner capabilities expose API/protocol compatibility and Codex login state.
- Telegram notification delivery now records success, retry, rejected, and
  unknown outcomes, attempt and end-to-end latency, pending outbox depth, and
  oldest pending age. Alerts cover stalled outboxes, persistent failures, and
  a measured delivery ratio below 99% once the sample is meaningful.
- Gateway image `sha-9814ecc26b4dcbd1bdcd44bebaccc0c85ce37d5d` is pinned
  to digest `sha256:4a7e2706458b38feb386f880aaa99598abebbe6df58eaba9f46bc9b4d5933167`.
- The matching runner image was published at digest
  `sha256:c2698c3f753ceeaed14a1f4145d7d2d4377e481973dcd9f92013647d0c52a1d9`;
  the GitOps template default is pinned to it, but publishing that template
  version and rebuilding the live workspace remain operator rollout steps. The
  current runner remains protocol-compatible with the gateway.

### Telegram plugin

- Authorized private chats have `/start` and `/help` journey guidance.
- Durable Codex cards provide status, retry, cancel, exact operation approval,
  question answering, and validated GitHub pull-request links.
- Concurrent controls for the same job/operation/question are serialized.
- Exact implementation preview cards queue work only after an authorized user
  approves; denials and expired previews create no job.
- Implementation rejection uses explicit `Do not queue` / `Implementation not
  queued` wording so dismissal cannot be mistaken for cancelling running work.
- Job status cards render the latest durable result with bounded, escaped text.
- Existing bot commands are preserved when installing the Hermes menu.
- Plugin image `sha-e17abf11082b179bcf1a99abba3cf6630c1f4050` is pinned to
  digest `sha256:7f247b3cd414a00e8ddbea43b255ae129884d8c8deb4ff3af68f225dc1dccf8d`.

## Verification completed locally

- Policy gateway: `go test ./...` passes, including PostgreSQL tests for the
  confirmation transaction and durable result visibility.
- Approval plugin: all 38 unit tests pass.
- GitOps: Helm lint and `tests/check-render.sh` pass.

## Remaining rollout order

1. Continue the P0 observation window started on 2026-10-24. Any silent
   failure, retry storm, or misleading health state resets the seven-day gate.
2. Verify GitHub App access independently. The analysis jobs did
   not exercise repository resolution or publishing, and must not be treated
   as evidence that implementation delegation is ready.
3. Run an end-user Telegram smoke test for help, connector reads, delegation
   preview, status, cancellation, and recovery notifications.
4. Run ten consecutive real P1 jobs, including login, quota, CI failure,
   cancellation, restart/unknown-outcome, and deployment-verification cases.

The MCP job-status response (`codex_get_job`) now includes the latest durable
Codex result alongside state and failure metadata. Telegram job status cards
also render that result with bounded, escaped text; end-user verification
remains part of the P1-D rollout.

## Remaining product work after P0/P1 rollout

- Queue position/limits, duplicate-job detection, repository mirror/cache,
  retention, fine-grained progress events, cost/token accounting, and the full
  independent end-to-end suite remain open.
- The built-in dashboard still renders operational controls such as
  `Restart Gateway` in upstream mode. The admin profile now enables the
  policy-gateway observer proxy, which redirects unsafe administration pages,
  rejects mutating HTTP methods server-side, removes operational controls, and
  displays a GitOps ownership banner. This remains subject to live UI smoke
  verification after rollout.
- P2 still needs scripted and human usability runs for homelab diagnosis,
  Paperless retrieval, Home Assistant, Wiki updates, and coding delegation.
- Rina isolation, typed Kubernetes mutations, authenticated browsing, email,
  and calendar remain gated exactly as described in the product plan; they
  must not be enabled merely because the base deployment is healthy.

