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

This backup-only change originally kept Frigate at 0.17.2 while the 0.18.0
upgrade was reviewed separately in PR #836. It replaces the backup proposal in
combined PR #849.

Local manifest validation:

```sh
helm dependency build kubernetes/services/frigate
kubernetes/services/frigate/tests/check-render.sh
```
## Frigate 0.18.0 upgrade (PR #836)

The main container now checks HTTP `/api/` on the internal port 5000 for
startup, readiness and liveness. A listening nginx socket alone no longer
marks the API ready. Startup allows 30 attempts at 10-second intervals
(five minutes); readiness and liveness remain gated until startup succeeds.
The existing single-instance rolling update (zero surge) is retained for the
RWO config PVC and exclusive camera/TPU use. API health does not establish
that cameras, recording, detection or hardware acceleration work.

### Configuration compatibility gate

The chart mounts `/config` from the writable Ceph PVC; it does not contain or
render Frigate's runtime `config.yaml`. Review the runtime configuration against
the [0.18.0 breaking changes](https://github.com/blakeblackshear/frigate/releases/tag/v0.18.0)
without exposing credentials or stream URLs. Check GenAI providers and roles,
snapshot `clean_copy`, zones and masks, removed recording/export/UI settings,
go2rtc hardware transcodes, detector support, semantic-search reindex needs,
and the internal listener used by probes.

Validate a writable disposable copy with the exact 0.18.0 image. Frigate's
migrator needs to update the copied file from config version `0.17-0` to
`0.18-0`. If an absolute mask cannot be converted because an isolated validator
probes a different detect resolution, explicitly set each camera's actual
`detect.width` and `detect.height` while still on 0.17, validate that change,
and rerun the disposable migration.

Do not validate the migration against a read-only config copy. Frigate logs a
failed migration and enters safe mode, but the validator can still exit zero
after validating the safe-mode config. Treat `Your config file is not valid`,
`unable to migrate`, or `Starting Frigate in safe mode` as failure regardless
of exit status.

Before deployment, create current config and database rollback artifacts. Use a
transactionally consistent SQLite backup, run `PRAGMA integrity_check` on the
copy, and retain the old image. These migration rollback inputs are not a
substitute for periodically testing the chart's NFS backup and a complete
restore procedure.

### Post-deployment verification

After a separately authorized deployment, verify the observed image/revision,
startup completion and restart count, rollout, Service endpoints, events and
migration logs. Check each camera, recordings/playback, Coral detection and
hardware acceleration. If migration exceeds the startup budget, investigate
logs before adjusting it. Restore the pre-upgrade config/database with the old
image for rollback; changing only the image may not undo data migrations.
