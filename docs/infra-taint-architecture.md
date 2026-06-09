# Infra Node Taint — Architecture & Decision Notes

## Background

This cluster runs 3 nodes with both `node-role.kubernetes.io/infra` label and ODF/Ceph device
labels. These nodes serve two purposes simultaneously:
1. Hosting OCP infrastructure components (Ingress, Registry, Monitoring)
2. Running ODF Ceph OSDs, MONs, and MGRs

Tainting these nodes with `NoSchedule` prevents arbitrary application workloads from consuming
resources that should be reserved for infrastructure.

---

## Taint Choice: NoSchedule vs NoExecute

| Effect | Behaviour | When to use |
|--------|-----------|-------------|
| `NoSchedule` | New pods without tolerations won't schedule; existing pods unaffected | **Phase 1** — apply tolerations, then taint |
| `PreferNoSchedule` | Soft — scheduler avoids tainted nodes but won't block | Not recommended for production infra isolation |
| `NoExecute` | Evicts existing pods without tolerations immediately | **Phase 2** — only after all tolerations confirmed |

**Recommended sequence**: Apply `NoSchedule` first. After full validation, optionally add
`NoExecute` to evict any remaining non-tolerating pods.

---

## Ceph Quorum Safety

ODF/Ceph requires MON quorum (2 out of 3 MONs must be healthy). Tainting all three nodes
simultaneously could cause a quorum loss window if any MON pod restarts without a toleration.

**Rule**: Taint one node, verify Ceph `HEALTH_OK`, then proceed to the next.

### MON quorum loss symptoms
```
ceph status → "mon quorum lost"
OSD WARN: "1 or more OSDs are down"
```

### Recovery if quorum is lost
```bash
# Force MON quorum recovery (use only as last resort)
oc rsh -n openshift-storage <tools-pod> ceph mon force-quorum <mon-name>
```

---

## Toleration Propagation Chain

```
StorageCluster (OCS)
  └── reconciles → CephCluster (rook-ceph)
        └── creates → MON / OSD / MGR / MDS pods
              └── each pod inherits tolerations from CephCluster placement spec
```

Because the OCS operator reconciles the CephCluster, tolerations set on the StorageCluster
`spec.placement` are the authoritative source. The CephCluster patch is belt-and-suspenders.

---

## ODF CSI DaemonSets

The ODF CSI plugin DaemonSets (`csi-cephfsplugin`, `csi-rbdplugin`) must run on **every node**
that mounts ODF volumes, including worker nodes. Their tolerations must include the infra taint
only if they need to run on infra nodes. For the CSI node plugins, they need to be on all nodes.

These are patched by `patch-daemonsets.sh`.

---

## Known Operator-Managed Resources

Some resources are continuously reconciled by operators and may have tolerations overwritten:

| Resource | Operator | Action |
|----------|----------|--------|
| `CephCluster` | OCS operator | Toleration in `StorageCluster` propagates down |
| `IngressController` | Ingress operator | Patch survives; operator respects spec |
| `cluster-monitoring-config` ConfigMap | Cluster Monitoring Operator | ConfigMap is the config source; CMO applies it |
| Subscription `config.tolerations` | OLM | Toleration applied to operator Deployment |
