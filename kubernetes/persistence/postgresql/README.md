# PostgreSQL 17 migration

PostgreSQL 17 runs beside the existing PostgreSQL 14 StatefulSet. During the
rehearsal, applications continue to use `postgresql.persistence:5432`; only
migration Jobs use `postgresql-v17.persistence:5432`.

The PostgreSQL 17 image is built from the official PostgreSQL image in
[`seungbemi/postgres-vectorchord`](https://github.com/seungbemi/postgres-vectorchord).

## Rehearsal

1. Confirm both StatefulSets and both client Services are healthy.
2. Create a safety dump before changing the old extensions:

   ```sh
   kubectl create -f kubernetes/persistence/postgresql/jobs/backup-job.yaml
   kubectl logs -n persistence -l app.kubernetes.io/name=postgresql-migration-backup -f
   ```

3. Run `check-vectors.sql` in the `immich` and `postgres` databases. It must
   return no dependent columns. Only after the safety dump is complete, remove
   the obsolete extension without `CASCADE`:

   ```sql
   DROP EXTENSION vectors;
   DROP SCHEMA IF EXISTS vectors;
   ```

4. Create a second migration dump and note the completed directory printed by
   the Job.
5. Create the restore configuration and restore Job:

   ```sh
   kubectl create configmap postgresql-migration -n persistence \
     --from-literal=DUMP_DIRECTORY=/backup/postgresql-migration/YYYYMMDDTHHMMSSZ
   kubectl create -f kubernetes/persistence/postgresql/jobs/restore-job.yaml
   kubectl logs -n persistence -l app.kubernetes.io/name=postgresql-migration-restore -f
   ```

6. Run `validate-v17.sql` against every restored database. PostgreSQL must be
   17.11, Immich must contain `vector` 0.8.6 and `vchord` 1.1.1, and no database
   may contain `vectors`.

Delete and recreate only the PostgreSQL 17 PVC before the final restore. Never
delete `data-postgresql-0`; it is the PostgreSQL 14 rollback volume.

## Cutover

The cutover change is deliberately not enabled in the rehearsal deployment.
During the maintenance window:

1. Disable Argo self-healing for database consumers and stop all writers.
2. Verify `pg_stat_activity` has no application sessions.
3. Reset the PostgreSQL 17 rehearsal PVC, take the final dump, restore, and
   validate it.
4. Set `postgresql.enabled=false` and `postgresql17.cutover=true`, then sync
   this application. The existing `postgresql` Service then selects only the
   PostgreSQL 17 pod. Rendering fails if cutover is enabled while the legacy
   dependency is still enabled.
5. Confirm the Service endpoint before restarting applications.
6. Keep `data-postgresql-0` for 14 days and until two PostgreSQL 17 backups have
   passed restore verification.

Rollback after applications have written to PostgreSQL 17 loses those new
writes. Stop writers immediately before reverting the cutover commit.
