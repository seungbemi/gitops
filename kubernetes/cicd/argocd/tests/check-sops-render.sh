#!/usr/bin/env bash
set -euo pipefail

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/../../../.." && pwd -P)
temporary_directory=$(mktemp -d)
trap 'rm -rf "$temporary_directory"' EXIT

argocd_chart="$repository_root/kubernetes/cicd/argocd"
argocd_render="$temporary_directory/argocd.yaml"
applications_render="$temporary_directory/applications.yaml"

helm dependency build "$argocd_chart" >/dev/null
helm template cicd "$argocd_chart" --namespace cicd >"$argocd_render"

grep -Fq 'name: cmp-sops-helm' "$argocd_render"
grep -Fq 'name: SOPS_AGE_KEY_FILE' "$argocd_render"
grep -Fq 'secretName: argocd-sops-age' "$argocd_render"
grep -Fq 'automountServiceAccountToken: false' "$argocd_render"
grep -Fq 'ghcr.io/getsops/sops:v3.13.3-alpine@sha256:ae501277bf742f1662e0f881f43dd8fd6798b489a8058e921dbf6cda597140ea' "$argocd_render"
grep -Fq 'quay.io/argoproj/argocd:v3.5.3@sha256:dd3f47d5a5e4da563a7a398506e892481b358a7cec50abdf320c71aa55904bfa' "$argocd_render"

for project_chart in \
  kubernetes/cicd/applications \
  kubernetes/ingress/_project \
  kubernetes/messaging/_project \
  kubernetes/monitoring/_project \
  kubernetes/persistence/_project \
  kubernetes/services/_project; do
  helm template validation "$repository_root/$project_chart" >>"$applications_render"
done

plugin_application_count=$(grep -Fc 'name: sops-helm' "$applications_render")
if [[ "$plugin_application_count" -ne 6 ]]; then
  echo "expected 6 SOPS Helm Applications, got $plugin_application_count" >&2
  exit 1
fi

bash -n "$repository_root/bootstrap.sh"
bash -n "$repository_root/scripts/sync-argocd-sops-key.sh"
echo "Argo CD SOPS integration rendered successfully"
