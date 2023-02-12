#!/bin/bash

# install cni weave
helm template -n kube-system kube-network ./kubernetes/kube-system/kube-network | kubectl apply -n kube-system -f -

# argocd install
helm template -n cicd cicd ./kubernetes/cicd/argocd --create-namespace --dependency-update | kubectl apply -n cicd -f -

bw get notes gitops-secrets | kubectl apply -n cicd -f -

