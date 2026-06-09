#!/usr/bin/env bash
# =============================================================================
# validate.sh
# Post-change health validation after infra node taint application.
# Run after apply-taints.sh completes.
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'
PASS="${GREEN}[PASS]${NC}"; WARN="${YELLOW}[WARN]${NC}"; FAIL="${RED}[FAIL]${NC}"

echo "================================================================"
echo " OCP Infra Node Taint — Post-Change Validation"
echo " $(date)"
echo "================================================================"

ERRORS=0

# ── 1. Node taints ────────────────────────────────────────────────────────────
echo -e "\n[1] Infra node taints:"
oc get nodes -l node-role.kubernetes.io/infra \
  -o custom-columns='NODE:.metadata.name,TAINTS:.spec.taints'

# ── 2. Pending pods (cluster-wide) ────────────────────────────────────────────
echo -e "\n[2] Pending pods (cluster-wide):"
PENDING=$(oc get pods --all-namespaces \
  --field-selector status.phase=Pending \
  -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase' \
  --no-headers 2>/dev/null)
if [[ -z "$PENDING" ]]; then
  echo -e "${PASS} No Pending pods found"
else
  echo -e "${WARN} Pending pods detected:"
  echo "$PENDING"
  ((ERRORS++))
fi

# ── 3. ODF pod health ─────────────────────────────────────────────────────────
echo -e "\n[3] ODF pods (non-Running/Completed):"
ODF_BAD=$(oc get pods -n openshift-storage \
  --field-selector='status.phase!=Running,status.phase!=Succeeded' \
  --no-headers 2>/dev/null | grep -v "^$" || true)
if [[ -z "$ODF_BAD" ]]; then
  echo -e "${PASS} All ODF pods Running or Completed"
else
  echo -e "${FAIL} Unhealthy ODF pods:"
  echo "$ODF_BAD"
  ((ERRORS++))
fi

# ── 4. Ceph cluster health ────────────────────────────────────────────────────
echo -e "\n[4] Ceph cluster health:"
TOOLS_POD=$(oc get pod -n openshift-storage -l app=rook-ceph-tools \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -z "$TOOLS_POD" ]]; then
  echo -e "${WARN} rook-ceph-tools not found — skipping"
else
  CEPH_STATUS=$(oc rsh -n openshift-storage "$TOOLS_POD" ceph status 2>/dev/null)
  echo "$CEPH_STATUS"
  if echo "$CEPH_STATUS" | grep -q "HEALTH_OK"; then
    echo -e "${PASS} Ceph: HEALTH_OK"
  else
    echo -e "${FAIL} Ceph NOT healthy"
    ((ERRORS++))
  fi
fi

# ── 5. Ceph OSD status ────────────────────────────────────────────────────────
echo -e "\n[5] Ceph OSD status:"
if [[ -n "$TOOLS_POD" ]]; then
  OSD_STAT=$(oc rsh -n openshift-storage "$TOOLS_POD" ceph osd status 2>/dev/null)
  echo "$OSD_STAT"
  UP_COUNT=$(echo "$OSD_STAT" | grep -c " up " || true)
  IN_COUNT=$(echo "$OSD_STAT" | grep -c " in " || true)
  echo -e "${PASS} OSDs up/in: ${UP_COUNT}/${IN_COUNT}"
fi

# ── 6. Ceph MON quorum ────────────────────────────────────────────────────────
echo -e "\n[6] Ceph MON quorum:"
if [[ -n "$TOOLS_POD" ]]; then
  MON_STAT=$(oc rsh -n openshift-storage "$TOOLS_POD" ceph mon stat 2>/dev/null)
  echo "$MON_STAT"
  if echo "$MON_STAT" | grep -q "quorum"; then
    echo -e "${PASS} MON quorum OK"
  else
    echo -e "${FAIL} MON quorum issue"
    ((ERRORS++))
  fi
fi

# ── 7. StorageCluster phase ───────────────────────────────────────────────────
echo -e "\n[7] StorageCluster phase:"
SC_PHASE=$(oc get storagecluster -n openshift-storage \
  -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
if [[ "$SC_PHASE" == "Ready" ]]; then
  echo -e "${PASS} StorageCluster: Ready"
else
  echo -e "${WARN} StorageCluster: ${SC_PHASE}"
fi

# ── 8. Monitoring stack ───────────────────────────────────────────────────────
echo -e "\n[8] Monitoring pod health:"
MON_BAD=$(oc get pods -n openshift-monitoring \
  --field-selector='status.phase!=Running,status.phase!=Succeeded' \
  --no-headers 2>/dev/null | grep -v "^$" || true)
if [[ -z "$MON_BAD" ]]; then
  echo -e "${PASS} All monitoring pods Running or Completed"
else
  echo -e "${WARN} Unhealthy monitoring pods:"
  echo "$MON_BAD"
fi

# ── 9. Ingress pods ───────────────────────────────────────────────────────────
echo -e "\n[9] Ingress (router) pods:"
oc get pods -n openshift-ingress -o wide --no-headers 2>/dev/null | \
  awk '{print "  " $1 "  " $3 "  " $7}'

# ── 10. Router pod node placement ────────────────────────────────────────────
echo -e "\n[10] Verifying router pods are on infra nodes:"
INFRA_NODES_LIST=$(oc get nodes -l node-role.kubernetes.io/infra \
  -o jsonpath='{.items[*].metadata.name}')
oc get pods -n openshift-ingress -o wide --no-headers 2>/dev/null | while read -r line; do
  NODE=$(echo "$line" | awk '{print $7}')
  NAME=$(echo "$line" | awk '{print $1}')
  if echo "$INFRA_NODES_LIST" | grep -qw "$NODE"; then
    echo -e "  ${GREEN}[OK]${NC}  ${NAME} → ${NODE}"
  else
    echo -e "  ${YELLOW}[WARN]${NC} ${NAME} → ${NODE} (not an infra node)"
  fi
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "================================================================"
if [[ $ERRORS -eq 0 ]]; then
  echo -e "${PASS} Validation passed — ${ERRORS} errors"
else
  echo -e "${FAIL} Validation found ${ERRORS} error(s) — review output above"
fi
echo "================================================================"
exit $ERRORS
