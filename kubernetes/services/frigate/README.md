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

The simple backup fix was merged separately. PR #836 upgrades Frigate to
0.18.0 without changing the backup implementation. Do not use the combined
backup/upgrade proposal in #849 as the upgrade prerequisite.

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

### Configuration compatibility gate — unresolved

The chart mounts `/config` from the writable Ceph PVC; it does not contain or
render Frigate's runtime `config.yml`. No live config or completed read-only
review findings were supplied to this job. Do not treat a Helm render as
validation of that configuration, and do not merge until the findings are
available and the applicable migrations are verified.

Review the actual sanitized runtime configuration against the
[0.18.0 breaking changes](https://github.com/blakeblackshear/frigate/releases/tag/v0.18.0)
and validate a copy with the exact 0.18.0 image before proceeding. In particular:

- Verify automatic migration of GenAI providers/roles, snapshot `clean_copy`,
  zones and masks; inspect any migration errors rather than assuming success.
- Remove obsolete `sync_recordings`, export `timelapse_args`, and
  `ui.date_format` / `ui.time_format` settings where present.
- Check hardware-transcoding go2rtc streams against the FFmpeg 8 migration
  instructions linked from the release notes; actual stream definitions are
  needed to determine the required change.
- Check detector support, GPU semantic-search reindex requirements and host
  compatibility if those features are configured.
- Confirm `networking.listen.internal` permits pod-IP HTTP probes on 5000
  and that no base-path override changes `/api/`. Keep credentials redacted.

### Operator verification under separate authorization

Before merge/deployment, run and restore-check the existing simple backup,
including a consistent stopped-Frigate database copy as recommended upstream.
Record the sanitized config validation/migration result. This PR does not run
backups, edit the PVC, mutate the cluster, or verify a live migration.

After a separately authorized deployment, verify the observed image/revision,
startup completion and restart count, rollout, Service endpoints, events and
migration logs. Check each camera, recordings/playback, Coral detection and
hardware acceleration. If migration exceeds the startup budget, investigate
logs before adjusting it. Restore the pre-upgrade config/database with the old
image for rollback; changing only the image may not undo data migrations.
