# monitoring

Cluster monitoring stack configuration for OpenShift, covering:

- Full `cluster-monitoring-config` with PVC storage classes, resource limits, and infra node pinning
- Alertmanager configuration with internal SMTP relay (no TLS, port 25)
- User workload monitoring config

---

## Files

| File | Description |
|------|-------------|
| `cluster-monitoring-config.yaml` | Full monitoring stack config: infra node pinning, PVCs, resource limits |
| `alertmanager-config-secret.yaml` | Alertmanager routing + SMTP receiver (base64-encoded) |
| `user-workload-monitoring-config.yaml` | User workload monitoring with infra node pinning |

---

## Apply

```bash
oc apply -f cluster-monitoring-config.yaml
oc apply -f alertmanager-config-secret.yaml
# Optional:
oc apply -f user-workload-monitoring-config.yaml
```

---

## Notes

- Cluster uses **CephFS** for Prometheus PVCs and **Ceph RBD** for Alertmanager PVCs
- SMTP relay: internal host, port 25, no TLS/auth
- Alertmanager gossip mesh uses port 9094 (ensure network policy allows pod-to-pod)
