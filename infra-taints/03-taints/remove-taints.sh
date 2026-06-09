#!/usr/bin/env bash
# =============================================================================
# remove-taints.sh
# ROLLBACK: Removes the infra taint from all infra nodes.
# Use this to reverse the taint operation if issues are detected.
#
# Usage:
#   bash remove-taints.sh              # remove NoSchedule taint
#   bash remove-taints.sh --dry-run    # preview only
#   bash remove-taints.sh --all        # remove both NoSchedule and NoExecute
# =============================================================================
set -euo pipefail

DRY_RUN=false
REMOVE_ALL=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --all)     REMOVE_ALL=true ;;
  esac
done

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

TAINT_KEY="node-role.kubernetes.io/infra"

echo "================================================================"
echo " OCP Infra Node Taint REMOVAL (Rollback)"
$DRY_RUN && echo " MODE: DRY RUN"
$REMOVE_ALL && echo " Removing: NoSchedule + NoExecute"
echo "================================================================"

INFRA_NODES=$(oc get nodes -l node-role.kubernetes.io/infra \
  -o jsonpath='{.items[*].metadata.name}')

for node in $INFRA_NODES; do
  echo -e "\nProcessing: ${node}"
  if $DRY_RUN; then
    echo -e "${YELLOW}[DRY-RUN]${NC} oc taint node ${node} ${TAINT_KEY}:NoSchedule-"
    $REMOVE_ALL && \
      echo -e "${YELLOW}[DRY-RUN]${NC} oc taint node ${node} ${TAINT_KEY}:NoExecute-"
  else
    oc taint node "$node" "${TAINT_KEY}:NoSchedule-" 2>/dev/null && \
      echo -e "${GREEN}[REMOVED]${NC} ${node}: NoSchedule taint removed" || \
      echo -e "${YELLOW}[SKIP]${NC}   ${node}: NoSchedule taint not present"
    if $REMOVE_ALL; then
      oc taint node "$node" "${TAINT_KEY}:NoExecute-" 2>/dev/null && \
        echo -e "${GREEN}[REMOVED]${NC} ${node}: NoExecute taint removed" || \
        echo -e "${YELLOW}[SKIP]${NC}   ${node}: NoExecute taint not present"
    fi
  fi
done

echo ""
echo "Taint removal complete. Verify node status:"
echo "  oc get nodes -l node-role.kubernetes.io/infra -o custom-columns='NODE:.metadata.name,TAINTS:.spec.taints'"
