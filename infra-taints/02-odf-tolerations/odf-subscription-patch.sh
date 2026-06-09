#!/usr/bin/env bash
# =============================================================================
# odf-subscription-patch.sh
# Patches the ODF operator Subscription so the operator pod itself tolerates
# the infra node taint.
#
# Usage:
#   bash odf-subscription-patch.sh              # live apply
#   bash odf-subscription-patch.sh --dry-run    # dry-run only
# =============================================================================
set -euo pipefail

DRY_RUN=""
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN="--dry-run=client"

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'

TOLERATION_PATCH='{
  "spec": {
    "config": {
      "tolerations": [
        {
          "key": "node-role.kubernetes.io/infra",
          "operator": "Exists",
          "effect": "NoSchedule"
        }
      ]
    }
  }
}'

echo "================================================================"
echo " Patching ODF Subscription — infra taint toleration"
[[ -n "$DRY_RUN" ]] && echo " MODE: DRY RUN"
echo "================================================================"

# Patch odf-operator subscription
if oc get subscription odf-operator -n openshift-storage &>/dev/null; then
  oc patch subscription odf-operator -n openshift-storage \
    --type='merge' -p "$TOLERATION_PATCH" $DRY_RUN
  echo -e "${GREEN}[PATCH]${NC} odf-operator subscription"
else
  echo -e "${RED}[WARN]${NC}  odf-operator subscription not found in openshift-storage"
fi

# Also patch ocs-operator subscription if present (older ODF deployments)
if oc get subscription ocs-operator -n openshift-storage &>/dev/null; then
  oc patch subscription ocs-operator -n openshift-storage \
    --type='merge' -p "$TOLERATION_PATCH" $DRY_RUN
  echo -e "${GREEN}[PATCH]${NC} ocs-operator subscription"
fi

# Patch mcg-operator subscription if present (NooBaa/Multi-Cloud Gateway)
if oc get subscription mcg-operator -n openshift-storage &>/dev/null; then
  oc patch subscription mcg-operator -n openshift-storage \
    --type='merge' -p "$TOLERATION_PATCH" $DRY_RUN
  echo -e "${GREEN}[PATCH]${NC} mcg-operator subscription"
fi

echo ""
echo "Verify operator pods are rescheduling:"
echo "  oc get pods -n openshift-storage -l app.kubernetes.io/part-of=odf-operator -w"
