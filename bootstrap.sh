#!/bin/bash

# install cni calico
helm template -n kube-system kube-network ./kubernetes/kube-system/kube-network | kubectl apply -f -

# argocd install
helm install -n cicd cicd ./kubernetes/cicd/argocd --create-namespace --dependency-update

bw get notes gitops-secrets | kubectl apply -f -

