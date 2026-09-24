#!/usr/bin/env bash
set -euo pipefail

command -v bw >/dev/null 2>&1 || {
    echo "Bitwarden CLI (bw) is required" >&2
    exit 1
}

command -v kubectl >/dev/null 2>&1 || {
    echo "kubectl is required" >&2
    exit 1
}

kubectl create namespace cicd --dry-run=client -o yaml | kubectl apply -f -

age_key_file=$(mktemp)
trap 'rm -f "$age_key_file"' EXIT HUP INT TERM
chmod 0600 "$age_key_file"
bw get notes gitops-sops-age-key >"$age_key_file"

if ! grep -Eq '^AGE-SECRET-KEY-1[0-9A-Z]+$' "$age_key_file"; then
    echo "Bitwarden note gitops-sops-age-key is not a valid age identity" >&2
    exit 1
fi

expected_recipient=age159380j9fv4z3frumefsfj92cuyw2xcdcdf87r03yue08zttx45kqy769pq
if ! grep -Fxq "# public key: $expected_recipient" "$age_key_file"; then
    echo "Bitwarden age identity does not match the repository recipient" >&2
    exit 1
fi

kubectl create secret generic argocd-sops-age \
    --namespace cicd \
    --from-file=keys.txt="$age_key_file" \
    --dry-run=client \
    -o yaml | kubectl apply -f -

echo "synchronized cicd/argocd-sops-age from Bitwarden"
