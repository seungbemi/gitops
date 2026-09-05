# Wiki.js

Wiki.js is the human-facing, canonical knowledge base for Hermes. Page content,
users, permissions, and history live in the existing PostgreSQL service. The
writable cache and temporary-content directory uses the NFS-backed
`wikijs-data` claim defined in the private GitOps repository; no Ceph volume or
NFS endpoint appears here. Human users sign in with local accounts, so no
Google or OIDC provider is required.

## Activation

1. Put the same strong database password in the private `wikijs-secrets`
   Secret and the Wiki.js section of the private PostgreSQL init script.
2. On an existing PostgreSQL volume, run the documented idempotent SQL once in
   the PostgreSQL pod. A clean PostgreSQL bootstrap runs it automatically.
3. Create the NFS directory configured by the private `wikijs-storage` chart
   and make it writable by UID/GID `1000` before deployment.
4. Deploy this chart, visit the private knowledge route, and complete Wiki.js
   setup with Sebe's local administrator account.
5. Disable public registration and remove all page access from Guests.
6. Create the top-level pages `sebe`, `rina`, and `shared`.
7. Create Rina's local human account and the groups described below.

PostgreSQL backups are the authoritative Wiki.js backup. Include the NFS folder
only to preserve transient files and any future filesystem storage module; it
must not be treated as a database backup.

PostgreSQL `initdb` scripts do not rerun against an existing volume. Database
password rotations therefore require rerunning the documented idempotent SQL
inside the PostgreSQL pod; changing the init script alone does not update a
running database.

## Human page permissions

Sebe remains the Wiki.js administrator. Create a `rina` group with only the
normal page and asset permissions needed by the UI, then add allow rules for
paths starting with `rina` and `shared`. Do not add a rule for `sebe`.

The intended human access matrix is:

| Path | Sebe | Rina |
|---|---|---|
| `sebe/**` | read/write/admin | none |
| `rina/**` | administrator access | read/write |
| `shared/**` | read/write/admin | read/write |

Sebe can technically administer every path because Wiki.js administrators are
not path-isolated. Use a separate non-administrator daily account if the Rina
area must also be private from the platform owner.

## Hermes API groups

Hermes must not receive a Wiki.js token directly. After the policy gateway is
deployed, create two API groups and keys:

- `hermes-sebe-bot`: allow only `sebe/**` and `shared/**`.
- `hermes-rina-bot`: allow only `rina/**` and `shared/**`.

Both bots may propose writes to `shared/**`. A write executes only after the
corresponding Telegram user approves the exact staged payload. Neither bot may
read or write the other user's private path.

Wiki.js 2.5 has a known GraphQL limitation: fetching a page through an API key
requires `manage:pages` or `delete:pages`, even for read-only access. Give the
API groups the minimum working global permission and matching path rules, then
enforce the narrower read/write/delete contract again in the policy gateway.
Never expose either API key to Hermes, the browser pod, or a human browser.

The gateway must reject paths outside the profile allowlist after URL decoding
and normalization, reject traversal and ambiguous Unicode forms, and must not
offer page deletion until a separately reviewed policy enables it.
