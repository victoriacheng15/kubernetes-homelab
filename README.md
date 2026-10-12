# Kubernetes Homelab

A learning and experimentation environment to understand how to operate Kubernetes across two physical machines using Proxmox VE.

---

## Architecture Overview

> [!NOTE]
> Tentative architecture, subject to change.

![Kubernetes Homelab Architecture](./docs/assets/architecture.png)

---

## Core Technical Stack

| Domain | Technology | Purpose |
| :--- | :--- | :--- |
| **Orchestration** | **k3s (embedded etcd)** | Lightweight Kubernetes engine managing API, controllers, and etcd state. |
| **Networking** | **Cilium (eBPF)** | Isolated VXLAN overlay mode. Protects host NICs and avoids altering LAN routing. |
| **Continuous Delivery** | **ArgoCD** | Declarative GitOps engine syncing manifests directly from Git. |
| **Observability** | **OpenTelemetry + Prometheus + Grafana** | Metrics scraping, OTLP distributed traces, and eBPF network flow inspection. |
| **Chaos Engineering** | **Chaos Mesh** | Controlled fault injection (latency, pod kills) to validate telemetry dashboards. |
| **Security & Auditing** | **Falco + Trivy + OWASP Juice Shop** | Runtime syscall monitoring, image scanning, and sandboxed attack drills. |
| **Storage & Persistence** | **Local-Path Provisioner** | Local disk mapping with `reclaimPolicy: Retain` to protect stored data from deletion. |
