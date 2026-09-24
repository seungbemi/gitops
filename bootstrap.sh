#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
"$SCRIPT_PATH/scripts/sync-argocd-sops-key.sh"

# install cni weave
helm template -n kube-system kube-network ./kubernetes/kube-system/kube-network | kubectl apply -n kube-system -f -

# argocd install
helm template -n cicd cicd ./kubernetes/cicd/argocd --create-namespace --dependency-update | kubectl apply -n cicd -f -

bw get notes gitops-secrets | kubectl apply -n cicd -f -
