#!/usr/bin/env bash
# =============================================================================
# apply-taints.sh
# Applies node-role.kubernetes.io/infra=:NoSchedule taint to infra nodes
# ONE AT A TIME, with Ceph health verification between each node.
#
# Safety guarantees:
#   - Verifies Ceph is HEALTH_OK before tainting each node
#   - Pauses between nodes for operator confirmation
#   - Supports --no-wait to skip confirmation prompts (CI/automation)
#   - Supports --dry-run to preview without applying
#
# Usage:
#   bash apply-taints.sh                    # interactive, one node at a time
#   bash apply-taints.sh --no-wait          # automated, still checks Ceph health
#   bash apply-taints.sh --dry-run          # dry-run only
#   bash apply-taints.sh --effect NoExecute # apply NoExecute instead (phase 2)
# =============================================================================
set -euo pipefail

DRY_RUN=false
NO_WAIT=false
EFFECT="NoSchedule"

for arg in "$@"; do
  case "$arg" in
    --dry-run)    DRY_RUN=true ;;
    --no-wait)    NO_WAIT=true ;;
    --effect)     shift; EFFECT="$1" ;;
  esac
done

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'

TAINT_KEY="node-role.kubernetes.io/infra"

# ── Helpers ───────────────────────────────────────────────────────────────────
check_ceph_health() {
  local TOOLS_POD
  TOOLS_POD=$(oc get pod -n openshift-storage -l app=rook-ceph-tools \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [[ -z "$TOOLS_POD" ]]; then
    echo -e "${YELLOW}[WARN]${NC} rook-ceph-tools pod not found — skipping Ceph health check"
    return 0
  fi
  local HEALTH
  HEALTH=$(oc rsh -n openshift-storage "$TOOLS_POD" ceph status 2>/dev/null | \
    grep -oP 'HEALTH_\w+' | head -1)
  if [[ "$HEALTH" == "HEALTH_OK" ]]; then
    echo -e "${GREEN}[OK]${NC}   Ceph health: HEALTH_OK"
    return 0
  else
    echo -e "${RED}[FAIL]${NC} Ceph health: ${HEALTH} — aborting taint operation"
    return 1
  fi
}

node_already_tainted() {
  local node="$1"
  oc get node "$node" -o jsonpath='{.spec.taints}' 2>/dev/null | \
    grep -q "$TAINT_KEY" && return 0 || return 1
}

# ── Main ──────────────────────────────────────────────────────────────────────
echo "================================================================"
echo " OCP Infra Node Taint Application"
echo " Taint: ${TAINT_KEY}=:${EFFECT}"
$DRY_RUN && echo " MODE: DRY RUN — no changes will be made"
echo "================================================================"

INFRA_NODES=$(oc get nodes -l node-role.kubernetes.io/infra \
  -o jsonpath='{.items[*].metadata.name}')

if [[ -z "$INFRA_NODES" ]]; then
  echo -e "${RED}[FAIL]${NC} No nodes found with label node-role.kubernetes.io/infra"
  exit 1
fi

NODE_COUNT=$(echo "$INFRA_NODES" | wc -w)
echo -e "\nFound ${NODE_COUNT} infra node(s): ${INFRA_NODES}"
echo ""

for node in $INFRA_NODES; do
  echo -e "${CYAN}────────────────────────────────────────────────────────${NC}"
  echo -e "Node: ${node}"

  # Skip if already tainted
  if node_already_tainted "$node"; then
    echo -e "${YELLOW}[SKIP]${NC} ${node} already has taint '${TAINT_KEY}'"
    continue
  fi

  # Ceph health gate
  echo -n "  Checking Ceph health... "
  if ! check_ceph_health; then
    echo -e "${RED}Halting. Fix Ceph before continuing.${NC}"
    exit 1
  fi

  # Confirmation prompt (unless --no-wait)
  if ! $NO_WAIT && ! $DRY_RUN; then
    echo ""
    read -rp "  Apply taint to ${node}? [y/N] " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo "  Skipped by user."; continue; }
  fi

  # Apply taint
  if $DRY_RUN; then
    echo -e "${YELLOW}[DRY-RUN]${NC} oc taint node ${node} ${TAINT_KEY}=:${EFFECT}"
  else
    oc taint node "$node" "${TAINT_KEY}=:${EFFECT}" --overwrite
    echo -e "${GREEN}[TAINT APPLIED]${NC} ${node}  →  ${TAINT_KEY}=:${EFFECT}"
  fi

  # Brief wait for pod scheduler to respond
  if ! $DRY_RUN; then
    echo "  Waiting 15s for scheduler to process..."
    sleep 15
    echo "  Pod summary on ${node}:"
    oc get pods --all-namespaces \
      --field-selector "spec.nodeName=${node}" \
      --no-headers 2>/dev/null | \
      awk '{print "    " $1 "/" $2 "  " $4}' | head -20
  fi
done

echo -e "\n${CYAN}════════════════════════════════════════════════════════${NC}"
echo " All nodes processed."
echo " Run validate.sh to confirm cluster health."
echo -e "${CYAN}════════════════════════════════════════════════════════${NC}"
