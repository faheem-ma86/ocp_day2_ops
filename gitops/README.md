# gitops

ArgoCD AppProject and Application templates for both ArgoCD operand instances.

---

## Files

| File | Description |
|------|-------------|
| `platform-appproject.yaml` | AppProject for platform/cluster-scoped GitOps |
| `app-appproject.yaml` | AppProject for application-scoped GitOps (dev/test namespaces) |
| `platform-application-template.yaml` | Application template for platform-level resources |
| `app-application-template.yaml` | Application template for application-level resources |

---

## Usage

Copy and customise the templates for each application or platform component.
Commit the resulting files to your GitOps repository and let ArgoCD sync them.

```bash
# Platform instance
oc apply -f platform-appproject.yaml -n openshift-gitops

# Application instance
oc apply -f app-appproject.yaml -n development
```
