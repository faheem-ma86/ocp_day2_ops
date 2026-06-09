#!/usr/bin/env bash
# =============================================================================
# preflight-check.sh
# Pre-change validation for infra node taint operation.
# Run this BEFORE applying any tolerations or taints.
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'
PASS="${GREEN}[PASS]${NC}"; WARN="${YELLOW}[WARN]${NC}"; FAIL="${RED}[FAIL]${NC}"

echo "================================================================"
echo " OCP Infra Node Taint — Pre-flight Check"
echo " $(date)"
echo "================================================================"

# ── 1. oc connectivity ────────────────────────────────────────────────────────
echo -e "\n[1] Checking oc connectivity..."
if oc whoami &>/dev/null; then
  echo -e "${PASS} Logged in as: $(oc whoami)"
else
  echo -e "${FAIL} Not logged in. Run: oc login"
  exit 1
fi

# ── 2. cluster-admin check ────────────────────────────────────────────────────
echo -e "\n[2] Checking cluster-admin privileges..."
if oc auth can-i '*' '*' --all-namespaces &>/dev/null; then
  echo -e "${PASS} cluster-admin confirmed"
else
  echo -e "${FAIL} Insufficient privileges — cluster-admin required"
  exit 1
fi

# ── 3. Infra nodes ────────────────────────────────────────────────────────────
echo -e "\n[3] Infra nodes:"
INFRA_NODES=$(oc get nodes -l node-role.kubernetes.io/infra \
  -o jsonpath='{.items[*].metadata.name}')
if [[ -z "$INFRA_NODES" ]]; then
  echo -e "${FAIL} No nodes found with label node-role.kubernetes.io/infra"
  exit 1
fi
for node in $INFRA_NODES; do
  STATUS=$(oc get node "$node" -o jsonpath='{.status.conditions[-1].type}')
  echo -e "${PASS} $node  [${STATUS}]"
done

# ── 4. Existing taints ────────────────────────────────────────────────────────
echo -e "\n[4] Existing taints on infra nodes:"
oc get nodes -l node-role.kubernetes.io/infra \
  -o custom-columns='NODE:.metadata.name,TAINTS:.spec.taints' | \
  sed 's/<none>/  (none)/'

# ── 5. Ceph cluster health ────────────────────────────────────────────────────
echo -e "\n[5] ODF / Ceph cluster health..."
TOOLS_POD=$(oc get pod -n openshift-storage -l app=rook-ceph-tools \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -z "$TOOLS_POD" ]]; then
  echo -e "${WARN} rook-ceph-tools pod not found — skipping Ceph health check"
  echo "       Deploy with: oc patch OCSInitialization ocsinit -n openshift-storage"
  echo "       --type json --patch '[{\"op\":\"replace\",\"path\":\"/spec/enableCephTools\",\"value\":true}]'"
else
  CEPH_HEALTH=$(oc rsh -n openshift-storage "$TOOLS_POD" ceph status 2>/dev/null)
  if echo "$CEPH_HEALTH" | grep -q "HEALTH_OK"; then
    echo -e "${PASS} Ceph status: HEALTH_OK"
  else
    echo -e "${FAIL} Ceph is NOT healthy — do not proceed with tainting"
    echo "$CEPH_HEALTH"
    exit 1
  fi
fi

# ── 6. ODF pods running ───────────────────────────────────────────────────────
echo -e "\n[6] ODF pod status (non-Running/Completed):"
NOT_RUNNING=$(oc get pods -n openshift-storage \
  --field-selector='status.phase!=Running,status.phase!=Succeeded' \
  -o custom-columns='NAME:.metadata.name,STATUS:.status.phase' 2>/dev/null | tail -n +2)
if [[ -z "$NOT_RUNNING" ]]; then
  echo -e "${PASS} All ODF pods are Running or Completed"
else
  echo -e "${WARN} Some ODF pods are not in Running state:"
  echo "$NOT_RUNNING"
fi

# ── 7. Monitoring pods ────────────────────────────────────────────────────────
echo -e "\n[7] Monitoring pod status (non-Running/Completed):"
MON_NOT_RUNNING=$(oc get pods -n openshift-monitoring \
  --field-selector='status.phase!=Running,status.phase!=Succeeded' \
  -o custom-columns='NAME:.metadata.name,STATUS:.status.phase' 2>/dev/null | tail -n +2)
if [[ -z "$MON_NOT_RUNNING" ]]; then
  echo -e "${PASS} All monitoring pods are Running or Completed"
else
  echo -e "${WARN} Some monitoring pods are not in Running state:"
  echo "$MON_NOT_RUNNING"
fi

# ── 8. StorageCluster phase ───────────────────────────────────────────────────
echo -e "\n[8] StorageCluster status:"
SC_PHASE=$(oc get storagecluster -n openshift-storage \
  -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
if [[ "$SC_PHASE" == "Ready" ]]; then
  echo -e "${PASS} StorageCluster phase: Ready"
else
  echo -e "${WARN} StorageCluster phase: ${SC_PHASE}"
fi

# ── 9. Pods currently on infra nodes ─────────────────────────────────────────
echo -e "\n[9] Pods currently scheduled on infra nodes:"
for node in $INFRA_NODES; do
  COUNT=$(oc get pods --all-namespaces \
    --field-selector "spec.nodeName=${node}" \
    --no-headers 2>/dev/null | wc -l)
  echo "    $node  →  ${COUNT} pods"
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "================================================================"
echo " Pre-flight complete. Review any [WARN] or [FAIL] items above."
echo " Proceed only when all checks are [PASS] or acceptable [WARN]."
echo "================================================================"
