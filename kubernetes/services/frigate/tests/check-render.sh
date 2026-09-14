#!/usr/bin/env bash
set -euo pipefail
chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rendered="$(mktemp)"
trap 'rm -f "$rendered"' EXIT
helm lint "$chart_dir" --strict
for release in frigate frigate-test; do
  helm template "$release" "$chart_dir" --namespace services > "$rendered"
  python3 - "$rendered" "$release" <<'PY'
from pathlib import Path
import re
import sys
text = Path(sys.argv[1]).read_text()
release = sys.argv[2]
docs = re.split(r"^---\s*$", text, flags=re.M)
def resource(kind):
    return next(doc for doc in docs if re.search(r"^kind: " + kind + r"$", doc, re.M))
cron = resource("CronJob")
deploy = resource("Deployment")
pvc = resource("PersistentVolumeClaim")
assert 'storageClassName: "ceph-block"' in pvc
claim = re.search(r"^  name: (.+)$", pvc, re.M)[1]
assert f"claimName: {claim}" in cron and f"claimName: {claim}" in deploy
assert re.search(r"mountPath: /config\n\s+name: config-folder\n\s+readOnly: true", cron)
assert "/volume1/LTS/backups/frigate" in cron and "server: diskstation.local" in cron
assert "/media/frigate" not in cron and "/volume1/LTS/frigate" not in cron
assert "/volume1/LTS/frigate" in deploy
assert "topologyKey: kubernetes.io/hostname" in cron
assert "app.kubernetes.io/controller: main" in cron
assert f"app.kubernetes.io/instance: '{release}'" in cron
assert "activeDeadlineSeconds: 1800" in cron and "concurrencyPolicy: Forbid" in cron
assert "@sha256:9ba6d8cbebf0fb6546ae71f2a1c14f6ffd2fdab83af7fa5669734ef30ad48844" in cron
assert f"name: {release}-backup-script" in cron
assert "backup.py: |" in resource("ConfigMap")
assert "ghcr.io/blakeblackshear/frigate:0.18.0" in deploy
assert re.search(r"startupProbe:\n\s+failureThreshold: 60\n.*\n\s+periodSeconds: 5", deploy)
print(f"Verified {release}: PVC, read-only source, NFS scope, scheduling, image and startup probe")
PY
done
PYTHONDONTWRITEBYTECODE=1 python3 "$chart_dir/tests/test_backup.py"
