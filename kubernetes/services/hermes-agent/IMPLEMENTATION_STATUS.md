# Hermes usable-product implementation status

Last reviewed: 2026-10-23

This file records evidence and phase gates. A local implementation, a merged
change, a healthy rollout, and a passed reliability gate are different states;
do not mark a phase complete by inferring one from another.

## Current live baseline

- Argo CD reports `hermes-admin` synced and healthy in `services`.
- The live Hermes containers still run `v2026.9.24`; the `v0.22.5` upgrade in
  this chart has not been rolled out as of this review.
- Recent policy-gateway logs show an expired Coder credential returning HTTP
  401 every ten seconds. Rotate the credential before delegation acceptance
  testing. The new gateway implementation classifies this as `needs_login` and
  closes the active attempt instead of retrying indefinitely, but that behavior
  is not live yet.
- Recent Hermes logs show intermittent Telegram path fallback events. Delivery
  has not yet been measured for the seven-day P0 reliability window.
- The dashboard is enabled on an internal route with basic authentication.
  Authentik OIDC is chart-supported, but no Hermes OIDC client/secret is
  provisioned yet.

## Implemented, awaiting GitOps merge and rollout

### GitOps chart

- Hermes is pinned consistently to `v0.22.5` and immutable multi-architecture
  digest `sha256:9c5561579f3ffdf333401797094ac3a743738d6c25d40f4331c7bf77b694238d`.
- An init check compares `hermes --version` with `Chart.appVersion` and blocks
  a mismatched rollout.
- Configuration schema version 51 is explicit and the removed
  `cron.model_drift_guard` key is no longer rendered.
- The dashboard is labelled as an administration observer; GitOps-owned
  `config.yaml` and `SOUL.md` are mounted read-only.
- Optional Authentik OIDC scopes and client-secret wiring is available.
- Alerts cover Coder `needs_login` and prolonged quota waits.

### Policy gateway and runner

- Implementation jobs resolve their starting revision to an exact GitHub
  commit before the durable job is inserted.
- Coder, runner protocol, and Codex login preflights are classified as
  authentication, quota, transient, or permanent failures.
- Authentication failures pause the affected job in `needs_login`; quota and
  transient failures use bounded backoff without replaying an unknown attempt.
- Telegram notifications and loopback endpoints provide durable status, retry,
  and cancellation controls.
- Runner capabilities expose API/protocol compatibility and Codex login state.
- Gateway image `sha-bc04852304ae9d029ef134f05dd6f149331beb85` is pinned
  to digest `sha256:57b6ef9f80df0f98b355fcb3dfb35a009ae6f979052a7ff07de6cc8a6625e502`.
- The matching runner image was published at digest
  `sha256:3188d113316a63d027c6d31c36110bee6cb933df7fa88d8c7efd303064bd6f2d`;
  update the Coder template/workspace before enabling jobs against the new
  gateway protocol.

### Telegram plugin

- Authorized private chats have `/start` and `/help` journey guidance.
- Durable Codex cards provide status, retry, cancel, exact operation approval,
  question answering, and validated GitHub pull-request links.
- Concurrent controls for the same job/operation/question are serialized.
- Existing bot commands are preserved when installing the Hermes menu.
- Plugin image `sha-e6f5dae37698661dd123833fe873faab667677ee` is pinned to
  digest `sha256:b16b3e110764ef7ddf87ae4cfd88f3046c97bdb2c86fa51d3eca0cc089ad7738`.

## Verification completed locally

- Policy gateway: `go test ./...` passes, including integration tests that bind
  temporary loopback ports.
- Approval plugin: all 35 unit tests pass.
- GitOps: Helm lint and `tests/check-render.sh` pass.

## Required rollout order

1. Rotate the Coder credential and validate it without exposing the token.
2. Merge and publish the policy-gateway, runner, and approval-plugin images.
3. Replace their GitOps image digests with the published immutable digests.
4. Provision an Authentik OIDC client and dashboard Secret, then replace basic
   authentication in the private profile.
5. Canary the Hermes `v0.22.5` chart and verify the runtime version, dashboard
   auth, Telegram delivery, dependency health, job controls, and rollback.
6. Run the seven-day P0 observation window. Any silent failure, retry storm, or
   misleading health state resets the gate.
7. Run ten consecutive real P1 jobs, including login, quota, CI failure,
   cancellation, restart/unknown-outcome, and deployment-verification cases.

## Remaining product work after P0/P1 rollout

- Hard-enforced implementation-job confirmation previews and immutable
  backend/model/reasoning policy fields remain to be added. Prompt guidance is
  not an adequate authorization boundary.
- Queue position/limits, duplicate-job detection, repository mirror/cache,
  retention, fine-grained progress events, cost/token accounting, and the full
  independent end-to-end suite remain open.
- P2 still needs scripted and human usability runs for homelab diagnosis,
  Paperless retrieval, Home Assistant, Wiki updates, and coding delegation.
- Rina isolation, typed Kubernetes mutations, authenticated browsing, email,
  and calendar remain gated exactly as described in the product plan; they
  must not be enabled merely because the base deployment is healthy.

