#!/usr/bin/env zsh
set -euo pipefail

TARGET_MINOR="${1:-}"

if [[ -z "${TARGET_MINOR}" ]]; then
    echo "Usage: $0 <minor-version>"
    echo "Example: $0 1.33"
    exit 1
fi

if [[ ! "${TARGET_MINOR}" =~ '^1\.[0-9]+$' ]]; then
    echo "ERROR: invalid Kubernetes minor version: ${TARGET_MINOR}"
    exit 1
fi

MASTERS=(
    "master1:rasp-master-1:first"
    "master2:rasp-master-2:normal"
    "master3:rasp-master-3:normal"
)

WORKERS=(
    "worker1:nuc-worker-1"
    "worker2:nuc-worker-2"
    "worker3:nuc-worker-3"
    "worker4:mac-worker-1"
)

run_remote() {
    local host="$1"
    local script="$2"
    shift 2

    local args=""
    local arg
    local escaped

    for arg in "$@"; do
        escaped="${(q)arg}"
        args+=" ${escaped}"
    done

    ssh -tt "${host}" \
        "cd \"\$HOME/kube\" && ./${script}${args}"
}

check_node_ready() {
    local node="$1"
    local node_status=""

    echo "Waiting for ${node} to become Ready..."

    for i in {1..60}; do
        node_status="$(
            kubectl get node "${node}" \
                -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' \
                2>/dev/null || true
        )"

        if [[ "${node_status}" == "True" ]]; then
            echo "${node} is Ready"
            return 0
        fi

        sleep 5
    done

    echo
    echo "ERROR: ${node} did not become Ready"
    kubectl get node "${node}" -o wide || true
    return 1
}

check_cluster() {
    echo
    echo "======================================"
    echo "Cluster status"
    echo "======================================"

    kubectl get nodes

    echo
    echo "Non-running pods:"
    kubectl get pods -A \
        --field-selector=status.phase!=Running,status.phase!=Succeeded \
        || true

    echo
    echo "API readiness:"
    kubectl get --raw='/readyz?verbose'

    echo
    echo "Versions:"
    kubectl get nodes \
        -o custom-columns='NAME:.metadata.name,VERSION:.status.nodeInfo.kubeletVersion,ARCH:.status.nodeInfo.architecture'
}

preflight() {
    echo
    echo "======================================"
    echo "Preflight"
    echo "======================================"

    echo "kubectl context:"
    kubectl config current-context

    echo
    kubectl get nodes

    echo
    echo "Checking SSH connectivity..."

    local item host node mode

    for item in "${MASTERS[@]}"; do
        IFS=: read -r host node mode <<< "${item}"

        printf '%-10s ' "${host}:"

        ssh \
            -o BatchMode=yes \
            -o ConnectTimeout=5 \
            "${host}" \
            hostname
    done

    for item in "${WORKERS[@]}"; do
        IFS=: read -r host node <<< "${item}"

        printf '%-10s ' "${host}:"

        ssh \
            -o BatchMode=yes \
            -o ConnectTimeout=5 \
            "${host}" \
            hostname
    done

    echo
    echo "Preflight OK."
}

upgrade_master() {
    local host="$1"
    local node="$2"
    local mode="$3"

    echo
    echo "======================================"
    echo "Upgrading control plane: ${node}"
    echo "======================================"

    #
    # Always regenerate target config immediately before upgrading.
    #
    run_remote "${host}" kube-prepare.sh "${TARGET_MINOR}"

    if [[ "${mode}" == "first" ]]; then
        run_remote "${host}" kube-upgrade-first-control-plane.sh
    else
        run_remote "${host}" kube-upgrade-node.sh
    fi

    echo
    echo "Draining ${node}..."

    kubectl drain "${node}" \
        --ignore-daemonsets \
        --delete-emptydir-data

    echo
    echo "Upgrading kubelet on ${node}..."

    run_remote "${host}" kube-upgrade-kubelet.sh

    echo
    echo "Uncordoning ${node}..."

    kubectl uncordon "${node}"

    check_node_ready "${node}"
    check_cluster
}

upgrade_worker() {
    local host="$1"
    local node="$2"

    echo
    echo "======================================"
    echo "Upgrading worker: ${node}"
    echo "======================================"

    #
    # Always regenerate target config immediately before upgrading.
    #
    run_remote "${host}" kube-prepare.sh "${TARGET_MINOR}"

    run_remote "${host}" kube-upgrade-node.sh

    echo
    echo "Draining ${node}..."

    kubectl drain "${node}" \
        --ignore-daemonsets \
        --delete-emptydir-data

    echo
    echo "Upgrading kubelet on ${node}..."

    run_remote "${host}" kube-upgrade-kubelet.sh

    echo
    echo "Uncordoning ${node}..."

    kubectl uncordon "${node}"

    check_node_ready "${node}"
    check_cluster
}

main() {
    echo
    echo "Kubernetes cluster upgrade"
    echo "Target minor: ${TARGET_MINOR}"
    echo

    preflight
    check_cluster

    echo
    read "answer?Continue with Kubernetes ${TARGET_MINOR} upgrade? [y/N] "

    case "${answer}" in
        y|Y|yes|YES)
            ;;
        *)
            echo "Cancelled."
            exit 0
            ;;
    esac

    echo
    echo "======================================"
    echo "Upgrading control planes sequentially"
    echo "======================================"

    local item host node mode

    for item in "${MASTERS[@]}"; do
        IFS=: read -r host node mode <<< "${item}"

        upgrade_master \
            "${host}" \
            "${node}" \
            "${mode}"
    done

    echo
    echo "======================================"
    echo "Upgrading workers sequentially"
    echo "======================================"

    for item in "${WORKERS[@]}"; do
        IFS=: read -r host node <<< "${item}"

        upgrade_worker \
            "${host}" \
            "${node}"
    done

    echo
    echo "======================================"
    echo "Upgrade complete"
    echo "======================================"

    check_cluster
}

main "$@"
