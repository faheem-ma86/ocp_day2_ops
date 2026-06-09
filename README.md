# ocp_day2_ops

A GitOps-ready collection of Day 2 operational manifests and runbooks for OpenShift 4.x clusters.
Designed for production environments running OpenShift Data Foundation (ODF/Ceph) on infrastructure nodes.

---

## Repository Structure

```
ocp_day2_ops/
├── infra-taints/                    # Infra node taint + toleration runbook
│   ├── 00-preflight/                # Pre-change validation scripts
│   ├── 01-tolerations/              # OCP core component tolerations
│   │   ├── monitoring/
│   │   ├── ingress/
│   │   ├── registry/
│   │   ├── logging/
│   │   └── daemonsets/
│   ├── 02-odf-tolerations/          # ODF/Ceph StorageCluster + CephCluster tolerations
│   ├── 03-taints/                   # Node taint manifests
│   └── 04-validation/               # Post-change validation scripts
├── rbac/                            # ArgoCD RBAC hardening manifests
├── monitoring/                      # Cluster monitoring configuration
├── gitops/                          # ArgoCD Application / AppProject manifests
├── scripts/                         # Reusable shell utilities
└── docs/                            # Extended runbooks and architecture notes
```

---

## Modules

| Module | Description | Status |
|--------|-------------|--------|
| [infra-taints](./infra-taints/README.md) | Apply taints to infra/ODF nodes safely | ✅ Ready |
| [rbac](./rbac/README.md) | ArgoCD RBAC least-privilege hardening | ✅ Ready |
| [monitoring](./monitoring/README.md) | Cluster monitoring config, Alertmanager SMTP | ✅ Ready |
| [gitops](./gitops/README.md) | ArgoCD AppProject and Application templates | ✅ Ready |

---

## Prerequisites

- OpenShift 4.x cluster (tested on 4.12+)
- `oc` CLI authenticated as `cluster-admin`
- ODF / OpenShift Data Foundation installed in `openshift-storage`
- ArgoCD / OpenShift GitOps installed (for `gitops/` and `rbac/` modules)

---

## Usage

Each module is self-contained with its own `README.md` and numbered manifests.
Apply them in order within each module directory.

```bash
# Example: apply infra taint module
cd infra-taints
bash 00-preflight/preflight-check.sh
oc apply -f 01-tolerations/monitoring/
oc apply -f 01-tolerations/ingress/
oc apply -f 01-tolerations/registry/
oc patch -f 02-odf-tolerations/storagecluster-tolerations.yaml --type merge
bash 03-taints/apply-taints.sh
bash 04-validation/validate.sh
```

---

## Safety Principles

1. **Tolerations before taints** — always apply tolerations to all workloads before tainting nodes
2. **NoSchedule first** — prevents new non-tolerating pods without evicting existing ones
3. **One node at a time** — preserves Ceph MON quorum (requires 2/3 healthy)
4. **Validate Ceph health between steps** — `ceph status` must show `HEALTH_OK` before proceeding
5. **Dry-run before apply** — all scripts support `--dry-run` flag

---

## Contributing

- Keep manifests idempotent (`oc apply` safe)
- Number files within directories to indicate apply order
- Add a `README.md` to every new module directory
- Test changes against a non-production cluster first

---

## Maintainer Notes

- Cluster uses CephFS for Prometheus PVCs and Ceph RBD for Alertmanager PVCs
- Infra nodes carry both `node-role.kubernetes.io/infra` and ODF device labels
- ArgoCD runs as two separate operand instances (cluster-admin scoped + app-admin scoped)
