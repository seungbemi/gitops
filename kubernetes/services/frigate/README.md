# Frigate upgrade and config backup

This chart upgrades Frigate from 0.17.2 to 0.18.0 (the upgrade originally
proposed in PR #836). The startup probe allows five minutes for startup and
config/database migrations before Kubernetes restarts the container.

## Backup scope and integrity

The chart-managed `config-folder` PVC renders as `frigate` for release `frigate`:
1 GiB, `ceph-block`, `ReadWriteOnce`. Both the application and backup mount that
same claim; the backup mount at `/config` is read-only. Required pod affinity
places the Job on the application's node so the RWO volume can be shared. If no
matching application pod exists, the Job will remain Pending and eventually
reach its deadline; it must not be treated as a successful backup.

The NFS destination remains `diskstation.local:/volume1/LTS/backups/frigate`.
Recordings and clips remain on `diskstation.local:/volume1/LTS/frigate`, mounted
only by the application at `/media/frigate`. They are a separate backup scope
and are **not** included in this config backup.

The backup uses a digest-pinned Python image for its standard-library SQLite
backup API. It opens source databases read-only, snapshots every `*.db` file,
and checks each snapshot with `PRAGMA integrity_check`. Committed SQLite WAL
transactions are included; live `*.db-wal`, `*.db-shm`, and `*.db-journal` files
are excluded. Other regular config files are copied with change detection.
Symlinks, missing config/database files, and failed integrity checks fail the
Job. SQLite read-only access must work with the live volume's permissions and
WAL/shared-memory state; there is deliberately no unsafe immutable-mode fallback.

Each run stages in `/tmp`, writes to a unique hidden `.partial-*` directory on
NFS, checks the gzip CRC and every archived file's SHA-256 against staging, then
publishes a unique `config-<UTC timestamp>-<random suffix>/` directory containing
`config.tar.gz` and `SHA256SUMS`. Existing backups, including `backups.tar.gz`,
are never replaced or pruned. A killed Job can leave a hidden partial directory;
partial directories are not verified backups. Monitor NFS capacity and arrange
retention separately. Staging uses up to 2 GiB of ephemeral storage.

## Required gate before merge/deployment

**A successful backup still must be run and verified in the cluster before
merge/deployment. This repository change and its local tests do not establish
that a cluster backup has succeeded.** Applying or running the candidate backup
requires separate operational authorization; this implementation job does not
change the cluster. Do not merge the upgrade simply to run the backup first.

For the candidate backup, obtain Job completion evidence, confirm the actual
source claim, read-only mount and node placement, and verify the published NFS
archive checksum. Restore to an isolated location, check the config is present,
run SQLite integrity checks, and confirm expected recent database records. Do
not print config contents or credentials into logs. Keep config editing paused
during the backup: SQLite snapshots are consistent individually, but the config
folder and multiple databases are not a single transactional snapshot.

The [0.18.0 release notes](https://github.com/blakeblackshear/frigate/releases/tag/v0.18.0)
recommend a stopped-application database copy before upgrading. This Job provides
an online SQLite snapshot; any separately required quiesced backup must be
planned with its pod-affinity requirement in mind, under separate authorization.
The runtime application YAML is held on the PVC, not in this repository, so its
migration has not been validated. Before upgrade, review its GenAI, zones/masks,
snapshot, removed option, and go2rtc hardware-transcoding settings against those
release notes. In particular, the FFmpeg 8/go2rtc compatibility adjustment is
conditional on runtime stream settings; no such settings exist in GitOps to
edit here. Validate migration and camera streams after an authorized upgrade.

## Local validation

With Helm and Python 3.11+ available, run from the repository root:

```sh
helm dependency build kubernetes/services/frigate
kubernetes/services/frigate/tests/check-render.sh
```

The checks lint and render two release names, verify the shared PVC, read-only
mount, backup/recording separation, RWO scheduling, pinned backup image and
startup probe, and exercise backup success and failure paths with a live WAL
fixture. No cluster access or application credentials are required.
