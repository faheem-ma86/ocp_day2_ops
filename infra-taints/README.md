# infra-taints

Safely apply `node-role.kubernetes.io/infra=:NoSchedule` taints to OpenShift infrastructure nodes
that are also running ODF/Ceph workloads — without disrupting cluster services or Ceph quorum.

---

## Directory Layout

```
infra-taints/
├── 00-preflight/
│   └── preflight-check.sh          # Pre-change health validation
├── 01-tolerations/
│   ├── monitoring/
│   │   └── cluster-monitoring-config.yaml
│   ├── ingress/
│   │   └── ingresscontroller.yaml
│   ├── registry/
│   │   └── imageregistry.yaml
│   ├── logging/
│   │   └── clusterlogging.yaml
│   └── daemonsets/
│       └── patch-daemonsets.sh
├── 02-odf-tolerations/
│   ├── storagecluster-tolerations.yaml
│   ├── cephcluster-tolerations.yaml
│   └── odf-subscription-patch.sh
├── 03-taints/
│   ├── apply-taints.sh             # Applies taints one node at a time
│   └── remove-taints.sh            # Rollback: removes taints from all infra nodes
└── 04-validation/
    └── validate.sh                 # Post-change health checks
```

---

## Ordered Execution

```
Step 1   bash 00-preflight/preflight-check.sh
Step 2   oc apply -f 01-tolerations/monitoring/cluster-monitoring-config.yaml
Step 3   oc apply -f 01-tolerations/ingress/ingresscontroller.yaml
Step 4   oc apply -f 01-tolerations/registry/imageregistry.yaml
Step 5   oc apply -f 01-tolerations/logging/clusterlogging.yaml   # if logging deployed
Step 6   bash 01-tolerations/daemonsets/patch-daemonsets.sh
Step 7   oc apply -f 02-odf-tolerations/storagecluster-tolerations.yaml
         oc apply -f 02-odf-tolerations/cephcluster-tolerations.yaml
         bash 02-odf-tolerations/odf-subscription-patch.sh
Step 8   Wait for all pods to re-stabilise (watch oc get pods -n openshift-storage)
Step 9   bash 03-taints/apply-taints.sh
Step 10  bash 04-validation/validate.sh
```

---

## Rollback

```bash
bash 03-taints/remove-taints.sh
```

---

## Taint Design

| Key | Value | Effect |
|-----|-------|--------|
| `node-role.kubernetes.io/infra` | `""` (empty) | `NoSchedule` |

`NoSchedule` is used as the first phase — it blocks new non-tolerating pods from scheduling
without evicting existing running pods. Apply `NoExecute` only after all tolerations
are confirmed in place and Ceph is healthy.
