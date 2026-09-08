# Paperless operations

Paperless keeps NFS consumer polling enabled at 300 seconds. Its startup probe
allows five minutes (5-second period, 60 failures); after startup, readiness is
checked every 10 seconds and liveness every 30 seconds, both with 3-second
timeouts.

Before Paperless starts, an init container running as UID/GID 1000 creates,
updates, and deletes a temporary file on each data, media, consume, and export
mount. This validates the permission that matters without weakening NFS root
squash. Nonfatal application `chown` warnings may be tolerated only after this
write test succeeds.

Smoke test search, metadata read, document download, and one approved metadata
update. Watch `kube_pod_container_status_restarts_total` for 48 hours after the
probe change; do not treat deployment success alone as acceptance.
