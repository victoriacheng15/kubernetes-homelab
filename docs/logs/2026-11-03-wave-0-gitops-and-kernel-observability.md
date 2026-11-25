# 2026-11-03: Wave 0 GitOps Deployment & Kernel Observability

## Overview

Deployed Wave 0 (Infrastructure) GitOps tier via ArgoCD, establishing baseline security, certificate management, and kernel runtime observability across the cluster using cert-manager, Kyverno, and Falco. Hardened GitOps CI pipelines with automated Kustomize compilation and Kubeconform schema validation. Resolved kernel eBPF driver initialization, container runtime socket routing, and Kyverno policy admission exemptions for Falco. Established local workstation cluster administration via an isolated remote kubeconfig, eliminating SSH copy-paste toil.

## Target Scope

* **Cluster Workloads (Wave 0):** `cert-manager` (v1.21.3), `kyverno` (v1.19.2), `falco` (v0.45.2)
* **GitOps & Bootstrapping:** `gitops/bootstrap/00-infrastructure.yaml`, `gitops/infrastructure/`
* **Continuous Integration:** `.github/workflows/ci.yaml`
* **Workstation Tooling:** `~/.kube/homelab.yaml`, `z-local/03-DNS-RESOLUTION.md`, `z-local/04-NGINX-TLS-DASHBOARDS.md`

## Key Changes

* Provisioned `cert-manager` v1.21.3 with a local three-stage PKI hierarchy (`selfsigned-issuer`, `homelab-root-ca`, and `homelab-ca-issuer`) pinned to `k8s-telemetry-01` via RFC 6902 JSON patches.
* Deployed `kyverno` v1.19.2 with a baseline `disallow-privileged-containers` ClusterPolicy pinned to `k8s-telemetry-01` via RFC 6902 JSON patches.
* Deployed `falco` v0.45.2 DaemonSet across all nodes using the modern eBPF driver (`engine.kind: modern_ebpf`), host kernel BTF mounts, and K3s containerd socket paths.
* Enhanced `.github/workflows/ci.yaml` with a dedicated `validate-gitops` job, implementing Tier 2 (Kustomize compilation) and Tier 3 (Kubeconform OpenAPI schema validation) gates for all GitOps pull requests.
* Enabled `SkipDryRunOnMissingResource=true` in `gitops/bootstrap/00-infrastructure.yaml` to unblock ArgoCD pre-flight dry-run evaluation on dynamically introduced CRDs.
* Exported K3s cluster credentials to `~/.kube/homelab.yaml` with the `k-home` alias, enabling the local workstation to communicate directly with the remote Kubernetes API server.

## Incidents & Root Cause Analysis

### 1. Falco Modern eBPF & Image Plugin Architecture

* **Symptom:** Falco DaemonSet crashed repeatedly on startup with `Error: Option 'cri' does not exist`, followed by `Plugin requirement not satisfied, must load one of: container (>= 0.4.0)`.
* **Root Cause:** Falco removed legacy `--cri` command-line flags in v0.39 and transitioned container metadata enrichment to modular plugins (`libcontainer.so`) in v0.41. Mounting a custom ConfigMap directly over `/etc/falco/falco.yaml` wiped out the base image's plugin declarations and rule files. Furthermore, manually redefining the plugin in a drop-in conflicted with the image's pre-existing `/etc/falco/config.d/falco.container_plugin.yaml`.
* **Resolution:** Preserved the upstream image's default `/etc/falco/falco.yaml` and modular configurations intact. Created a minimal drop-in at `/etc/falco/config.d/homelab.yaml` declaring only `engine.kind: modern_ebpf`. Mounted the host K3s socket (`/run/k3s/containerd/containerd.sock`) to the container's standard path (`/run/containerd/containerd.sock`), enabling Falco's native container plugin to connect automatically.

### 2. Kyverno Privileged Container Admission Policy Exemption

* **Symptom:** ArgoCD surfaced policy violation alerts on the Falco DaemonSet: `rule privileged-containers failed at path /spec/containers/0/securityContext/privileged/`.
* **Root Cause:** The `disallow-privileged-containers` ClusterPolicy excluded system namespaces (`kube-system`, `argocd`, `cilium`, `infrastructure`), but omitted `falco`. Because Falco requires `securityContext.privileged: true` to attach eBPF probes to kernel tracepoints, Kyverno flagged the daemon.
* **Resolution:** Added `- falco` to `exclude.any.resources.namespaces` in `gitops/infrastructure/kyverno/cluster-policies.yaml`, allowing Falco to run with necessary kernel tracing capabilities.

### 3. ArgoCD CRD Pre-Flight Dry Run Blocker

* **Symptom:** ArgoCD sync failed with `Resource not found in cluster: cert-manager.io/v1/Certificate:homelab-root-ca` and `kyverno.io/v1/ClusterPolicy:disallow-privileged-containers`.
* **Root Cause:** ArgoCD runs a dry-run schema validation against the Kubernetes API server before applying manifests. Because the CRDs and Custom Resources were deployed within the same application, the API server had not registered the schemas when the pre-flight check executed.
* **Resolution:** Added `SkipDryRunOnMissingResource=true` to `syncOptions` in `gitops/bootstrap/00-infrastructure.yaml`, instructing ArgoCD to bypass dry-run checks for Custom Resources whose CRDs are installed during the sync.

### 4. Workflow Friction: Remote Cluster Administration via Workstation Kubeconfig

* **Symptom:** Debugging cluster workloads required a slow, multi-minute feedback loop (edit locally, push to git, open PR, merge, wait for ArgoCD poll, SSH to control plane VM, inspect logs).
* **Root Cause:** The local development environment was not configured with a remote kubeconfig, treating the cluster as an isolated black box reachable only through SSH or GitOps commits.
* **Resolution:** Copied `/etc/rancher/k3s/k3s.yaml` from `k8s-cp-01` (`<CONTROL_PLANE_IP>`) to an isolated local file `~/.kube/homelab.yaml` and mapped it to a `k-home` shell alias, enabling the local workstation to communicate directly with the remote Kubernetes API server.

## Verification

??? note "Wave 0 Infrastructure Workloads State (`cert-manager`, `falco`, `kyverno`)"
    ```text
    NAMESPACE      NAME                                                READY   STATUS    RESTARTS   AGE
    cert-manager   cert-manager-6857c5fb9b-c782x                       1/1     Running   0          155m
    cert-manager   cert-manager-cainjector-5548dd9c6c-jxkl6            1/1     Running   0          155m
    cert-manager   cert-manager-webhook-db4b6c44b-x4tfh                1/1     Running   0          155m
    falco          falco-d6w6g                                         1/1     Running   0          2m15s
    falco          falco-mrdtz                                         1/1     Running   0          2m15s
    falco          falco-n2wz7                                         1/1     Running   0          2m15s
    kyverno        kyverno-admission-controller-7648cb8849-jf4vz       1/1     Running   0          155m
    kyverno        kyverno-background-controller-5468bb579-xbjhk       1/1     Running   0          155m
    kyverno        kyverno-cleanup-controller-7596c46688-7fkpq         1/1     Running   0          155m
    kyverno        kyverno-reports-controller-57c7bc78dc-7mfxv         1/1     Running   0          155m
    ```

??? note "Falco Modern eBPF Engine Initialization Logs"
    ```text
    Loading rules from:
       /etc/falco/falco_rules.yaml | schema validation: ok
    Enabled event sources: syscall
    Opening 'syscall' source with modern BPF probe.
    One ring buffer every '2' CPUs.
    Starting health webserver with threadiness 2, listening on 0.0.0.0:8765
    ```
