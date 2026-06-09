# rbac

ArgoCD RBAC hardening manifests for two isolated ArgoCD operand instances:

| Instance | Namespace | Scope |
|----------|-----------|-------|
| `openshift-gitops` | `openshift-gitops` | Cluster-admin (platform GitOps) |
| `argocd` | `development` | Application-admin (dev/test namespaces only) |

---

## Files

| File | Description |
|------|-------------|
| `cluster-admin-argocd-rbac-cm.yaml` | RBAC ConfigMap for cluster-admin ArgoCD instance |
| `app-admin-argocd-rbac-cm.yaml` | RBAC ConfigMap for application-admin ArgoCD instance |
| `cluster-admin-appproject.yaml` | AppProject for platform GitOps (cluster-scoped) |
| `app-admin-appproject.yaml` | AppProject for application GitOps (namespace-scoped) |

---

## Key Principles

- No `system:authenticated:oauth` in cluster-admin instance (prevents all OAuth users getting admin)
- Application-admin instance has no `exec` or cluster-write permissions
- Two instances are fully isolated — RBAC changes to one do not affect the other
- Custom ClusterRoles scoped to minimum required resources (`clusters, get` not `clusters, *`)
