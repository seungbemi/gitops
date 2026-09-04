# Wiki.js

Wiki.js is the human-facing, canonical knowledge base for Hermes. It uses the
existing PostgreSQL service in `persistence` and keeps writable application
data on a Ceph PVC. Human users sign in with local accounts; no Google or OIDC
provider is required.

## Activation

1. Put the same strong database password in the private
   `wikijs-database-bootstrap` and `wikijs-secrets` Secrets.
2. Enable `wikijsBootstrap` in the PostgreSQL chart and wait for the
   `wikijs-database-bootstrap` Argo hook to complete.
3. Deploy this chart, visit the private knowledge route, and complete Wiki.js
   setup with Sebe's local administrator account.
4. Disable public registration and remove all page access from Guests.
5. Create the top-level pages `sebe`, `rina`, and `shared`.
6. Create Rina's local human account and the groups described below.

The database bootstrap is deliberately separate from PostgreSQL `initdb`:
`initdb` scripts do not rerun against an existing volume. The bootstrap Job is
idempotent and creates only the non-superuser `wikijs` role and database.

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
