#!/usr/bin/env bash
# =============================================================================
# patch-daemonsets.sh
# Patches cluster-level DaemonSets that must run on ALL nodes (including
# infra/tainted nodes) to add the infra taint toleration.
#
# DaemonSets covered:
#   - node-exporter           (openshift-monitoring)
#   - machine-config-daemon   (openshift-machine-config-operator)
#   - multus                  (openshift-multus)
#   - network-metrics-daemon  (openshift-multus)
#   - ovnkube-node            (openshift-ovn-kubernetes)
#   - csi-node daemonsets     (openshift-storage)
#
# Usage:
#   bash patch-daemonsets.sh              # live apply
#   bash patch-daemonsets.sh --dry-run    # dry-run only
# =============================================================================
set -euo pipefail

DRY_RUN=""
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN="--dry-run=client"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'

TAINT_PATCH='[
  {
    "op": "add",
    "path": "/spec/template/spec/tolerations/-",
    "value": {
      "key": "node-role.kubernetes.io/infra",
      "operator": "Exists",
      "effect": "NoSchedule"
    }
  }
]'

patch_ds() {
  local ns="$1"
  local name="$2"
  if oc get daemonset "$name" -n "$ns" &>/dev/null; then
    # Check if toleration already present
    if oc get daemonset "$name" -n "$ns" \
        -o jsonpath='{.spec.template.spec.tolerations}' | \
        grep -q "node-role.kubernetes.io/infra"; then
      echo -e "${YELLOW}[SKIP]${NC}  ${ns}/${name}  (toleration already present)"
      return
    fi
    # Ensure tolerations array exists (add empty array if absent)
    oc patch daemonset "$name" -n "$ns" --type='json' \
      -p='[{"op":"test","path":"/spec/template/spec","value":{"tolerations":[]}}]' \
      &>/dev/null || \
    oc patch daemonset "$name" -n "$ns" --type='merge' \
      -p='{"spec":{"template":{"spec":{"tolerations":[]}}}}' \
      $DRY_RUN &>/dev/null || true

    oc patch daemonset "$name" -n "$ns" \
      --type='json' -p="$TAINT_PATCH" $DRY_RUN
    echo -e "${GREEN}[PATCH]${NC} ${ns}/${name}"
  else
    echo -e "${YELLOW}[SKIP]${NC}  ${ns}/${name}  (not found)"
  fi
}

echo "================================================================"
echo " Patching DaemonSets — infra taint toleration"
[[ -n "$DRY_RUN" ]] && echo " MODE: DRY RUN"
echo "================================================================"

echo -e "\n── Monitoring ───────────────────────────────────────────────"
patch_ds openshift-monitoring        node-exporter

echo -e "\n── Machine Config ───────────────────────────────────────────"
patch_ds openshift-machine-config-operator  machine-config-daemon

echo -e "\n── Multus / Networking ──────────────────────────────────────"
patch_ds openshift-multus            multus
patch_ds openshift-multus            network-metrics-daemon
patch_ds openshift-multus            multus-admission-controller

echo -e "\n── OVN ──────────────────────────────────────────────────────"
patch_ds openshift-ovn-kubernetes    ovnkube-node
patch_ds openshift-ovn-kubernetes    ovs-node

echo -e "\n── ODF / CSI ────────────────────────────────────────────────"
patch_ds openshift-storage           csi-cephfsplugin
patch_ds openshift-storage           csi-rbdplugin

echo ""
echo "================================================================"
echo " DaemonSet patching complete."
echo " Verify with: oc get pods -n openshift-storage -o wide"
echo "================================================================"
