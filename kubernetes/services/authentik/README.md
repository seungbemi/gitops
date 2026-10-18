# Authentik

Authentik is the central OpenID Connect identity provider for human-facing
services. The public issuer hostname is defined only in the private ingress
repository; PostgreSQL, metrics, and pod ports remain cluster-internal.

The release uses the shared PostgreSQL service and the `authentik` database and
role. Secret values come from `services/authentik-secrets` in the private
GitOps repository. Uploaded icons and other local media are retained on the
`authentik-media` Ceph PVC.

## Initial activation

1. Apply the PostgreSQL role/database provisioning to an existing database
   volume; the init script runs automatically only on a clean bootstrap.
2. Sync `service-secrets`, `authentik`, and the private ingress routes.
3. Visit `https://<private-ingress-host>/if/flow/initial-setup/` exactly once
   and set the initial `akadmin` password.
4. Create the named administrator account `seungbemi`, verify recovery and MFA,
   and retain `akadmin` only as a break-glass account.

Do not create OIDC applications or disable any application's local login until
the Authentik backup and recovery path has been tested.
