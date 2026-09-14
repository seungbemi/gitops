# Frigate config backup

The backup mounts the same chart-managed `config-folder` Ceph-block PVC as
Frigate, read-only at `/config`. Required pod affinity keeps the backup on
Frigate's node so the ReadWriteOnce claim can be shared. Without a matching
Frigate pod, the backup remains Pending.

The existing NFS destination is unchanged:
`diskstation.local:/volume1/LTS/backups/frigate`. The shell command writes tar
output to a temporary file on that destination, checks that it is non-empty,
and atomically renames it to `backups.tar.gz`. A failed tar command leaves the
previous archive intact. Each successful run replaces that archive. Recordings
on the separate `/media/frigate` mount are not included.

This is a plain file archive, not a transactionally consistent SQLite snapshot.
A non-empty archive does not establish database integrity or recoverability.
An operator must run and restore-check a backup in the cluster before relying
on it for an upgrade; no live backup is verified by this repository change.

Frigate stays at 0.17.2. The separate upgrade to 0.18.0 remains in PR #836.
This backup-only change replaces the backup proposal in combined PR #849;
neither existing PR is modified by this change.

Local manifest validation:

```sh
helm dependency build kubernetes/services/frigate
kubernetes/services/frigate/tests/check-render.sh
```
