# Kubernetes Homelab Documentation

Technical specifications, design decisions, and operational runbooks for a bare-metal Kubernetes cluster operating across dual-node Proxmox VE hardware and an external Raspberry Pi quorum witness.

For the narrative story behind the architectural choices and operational lessons, read [The Platform Journey](./journey.md).

---

## Why This Exists

Built to expand beyond single-machine experiments and disposable cloud setups, evolving the foundations of [observability-hub](https://github.com/victoriacheng15/observability-hub) across distributed physical infrastructure:

* **Distributed Topology:** Scales across multi-node hardware using an external Raspberry Pi tiebreaker to manage quorum and node failure domains.
* **Three-Tier Platform Lifecycle:** Enforces strict boundaries across infrastructure (OpenTofu), host OS baselines (Ansible), and workloads (ArgoCD).
* **Control Plane Isolation:** Isolates the control plane with `NoSchedule` taints to protect API stability.
* **Host Network Management:** Manages machine IP addressing via DHCP and static reservations across physical hosts and VMs.
* **Kernel Datapath & Routing:** Routes pod traffic via Cilium eBPF and VXLAN overlay without disrupting the home LAN.
* **Zero-Drift GitOps:** Reconciles all cluster services and platform tools automatically using ArgoCD.

---

## Platform Architecture Layers

![Platform Architecture Layers](./assets/platform-layers.png)

---

## Hardware

![Physical Topology](./assets/physical-topology.png)

| | Device | Node Name | Arch | RAM | Role |
| :---: | :--- | :--- | :--- | :--- | :--- |
| <img src="./assets/logos/proxmox.svg" alt="Proxmox" width="32"> | Mini PC | `pve-01` | x86_64 | 32 GB | Proxmox host (`k8s-cp-01`, `k8s-telemetry-01`) |
| <img src="./assets/logos/proxmox.svg" alt="Proxmox" width="32"> | Laptop | `pve-02` | x86_64 | 8 GB | Proxmox host (`k8s-app-01` worker) |
| <img src="./assets/logos/raspberrypi.svg" alt="Raspberry Pi" width="32"> | Raspberry Pi 3B | `rpi-01` | ARM64 | 1 GB | Corosync QDevice, Chrony NTP, and SSH Jumpbox |

---

## K8s Architecture Topology

![Kubernetes Homelab Architecture](./assets/architecture.png)

---

## Tech Stack

### Infrastructure & Gateway

| | Name | Description |
| :---: | :--- | :--- |
| <img src="./assets/logos/opentofu.svg" alt="OpenTofu" width="32"> | [OpenTofu](https://opentofu.org/) | Declarative virtual machine and LXC infrastructure provisioning via Proxmox API |
| <img src="./assets/logos/ansible.svg" alt="Ansible" width="32"> | [Ansible](https://www.ansible.com/) | Agentless OS baseline hardening, kernel tuning, and utility container automation |
| <img src="./assets/logos/nginx.svg" alt="Nginx" width="32"> | [Nginx](https://nginx.org/) | External reverse proxy gateway for unified internal DNS and NodePort routing |
| <img src="./assets/logos/pihole.svg" alt="Pi-hole" width="32"> | [Pi-hole](https://pi-hole.net/) | DNS sinkhole providing wildcard resolution (*.homelab.local) for LAN clients |

### Cluster Core & Networking

| | Name | Description |
| :---: | :--- | :--- |
| <img src="./assets/logos/kubernetes.svg" alt="Kubernetes" width="32"> | [Kubernetes (k3s)](https://k3s.io/) | Lightweight Kubernetes distribution with embedded etcd |
| <img src="./assets/logos/cilium.svg" alt="Cilium" width="32"> | [Cilium](https://cilium.io/) | eBPF-based CNI, isolated VXLAN overlay, kube-proxy replacement, Hubble |
| <img src="./assets/logos/argo.svg" alt="Argo CD" width="32"> | [Argo CD](https://argoproj.github.io/cd/) | GitOps continuous delivery engine syncing manifests directly from Git |
| <img src="./assets/logos/cert-manager.svg" alt="cert-manager" width="32"> | [cert-manager](https://cert-manager.io/) | Automated TLS certificate management and local CA issuance |

### Observability & Telemetry

| | Name | Description |
| :---: | :--- | :--- |
| <img src="./assets/logos/prometheus.svg" alt="Prometheus" width="32"> | [Prometheus](https://prometheus.io/) | Time-series metrics collection and monitoring |
| <img src="./assets/logos/grafana.svg" alt="Grafana" width="32"> | [Grafana](https://grafana.com/) | Visualization dashboards for metrics, traces, and Hubble flows |
| <img src="./assets/logos/opentelemetry.svg" alt="OpenTelemetry" width="32"> | [OpenTelemetry](https://opentelemetry.io/) | Distributed tracing and OTLP telemetry collection |
| <img src="./assets/logos/go.svg" alt="Podinfo" width="32"> | [Podinfo](https://github.com/stefanprodan/podinfo) | Cloud-native microservice for GitOps validation, metrics, and traffic shifting |

### Security & Chaos Engineering

| | Name | Description |
| :---: | :--- | :--- |
| <img src="./assets/logos/falco.svg" alt="Falco" width="32"> | [Falco](https://falco.org/) | Kernel runtime security daemon detecting unauthorized syscalls |
| <img src="./assets/logos/kyverno.svg" alt="Kyverno" width="32"> | [Kyverno](https://kyverno.io/) | Kubernetes-native admission controller and policy enforcement |
| <img src="./assets/logos/chaos-mesh.svg" alt="Chaos Mesh" width="32"> | [Chaos Mesh](https://chaos-mesh.org/) | Chaos engineering platform for controlled fault injection |
| <img src="./assets/logos/owasp.svg" alt="OWASP Juice Shop" width="32"> | [OWASP Juice Shop](https://owasp.org/www-project-juice-shop/) | Vulnerable web application for runtime security drills and policy hardening |
