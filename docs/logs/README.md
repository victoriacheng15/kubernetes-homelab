# Engineering Logs

Chronological record of physical hardware provisioning, cluster state transitions, operational debugging, and verification outputs.

| ID | Log Entry | Target Scope | Key Incidents Resolved |
| :--- | :--- | :--- | :--- |
| 001 | [Physical Cluster Initialization & QDevice Quorum](./2026-10-25-physical-cluster-initialization-and-qdevice-quorum.md) | `pve-01`, `pve-02`, `rpi-01`, `infra/` | `pmxcfs` join guest collision, Proxmox API 403 token permissions, QDevice NR state |
| 002 | [Platform Hierarchy & OpenTofu Hardening](./2026-10-26-platform-hierarchy-and-opentofu-hardening.md) | `infra/`, `ansible/`, `docs/assets/` | OpenTofu QEMU agent API starvation, container drift recreation |
| 003 | [Layer 3 Kubernetes Bootstrap & Cilium eBPF](./2026-10-27-layer-3-kubernetes-bootstrap-and-cilium.md) | `k3s`, `cilium`, `bootstrap/` | Cilium IPAM host subnet lockout, NodeRestriction worker onboarding |
| 004 | [Layer 2 DNS Sinkhole & Gateway Automation](./2026-11-02-layer-2-dns-and-gateway-automation.md) | `pihole`, `nginx`, `ansible/` | Pi-hole v6 FTL decoupling, Linux RFC 6762 mDNS multicast trap |
| 005 | [Wave 0 GitOps Deployment & Kernel Observability](./2026-11-03-wave-0-gitops-and-kernel-observability.md) | `gitops/`, `cert-manager`, `falco`, `kyverno` | Falco modular eBPF plugins, Kyverno privileged policy exemption, ArgoCD CRD dry-run blocker |
| 006 | [Infrastructure Drills & CNI Automation](./2026-11-05-infrastructure-drills-and-cni-automation.md) | `infra/`, `ansible/`, `bootstrap/` | Machine-ID DHCP collision, NodeRestriction admission, Cilium Helm boolean bug |
