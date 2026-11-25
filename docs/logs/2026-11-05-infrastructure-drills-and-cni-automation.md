# 2026-11-05: Infrastructure Drills & CNI Automation

## Overview

Executed automated infrastructure and cluster provisioning drills across OpenTofu, Ansible, and k3s. Refactored OpenTofu virtual machine declarations into declarative loops with dual-key SSH access, reorganized LXC utility containers on `pve-01`, and automated Kubernetes worker role labeling from the control plane. Resolved template machine-ID DHCP lease collisions, Kubernetes admission controller self-labeling constraints, and Cilium Helm schema typecast errors.

## Target Scope

* **Virtual Machines:** `k8s-cp-01`, `k8s-telemetry-01`, `k8s-app-01`
* **Containers (LXC):** `ansible`, `tailscale`, `nginx`, `pihole`
* **Provisioning & Automation:** `infra/`, `ansible/`, `bootstrap/`

## Key Changes

* Refactored OpenTofu VM definitions into declarative `for_each` loops with dual SSH key pairs (`admin_ssh_public_key` and `ansible_ssh_public_key`).
* Reorganized LXC utility container addressing, placing `ansible`, `tailscale`, `nginx`, and `pihole` on `pve-01`.
* Automated worker node role classification (`telemetry`, `app`) directly from the control plane via Ansible Play 3 using `kubectl label node`.
* Added `/dev/net/tun` cgroup passthrough rules to `tailscale` LXC configuration on `pve-01`.
* Standardized Cilium CNI deployment to target `workload=telemetry` for Hubble components.

## Incidents & Root Cause Analysis

### 1. Cloud-Init Golden Image Machine-ID Collision (Virtualization Layer)

* **Symptom:** Cloned Kubernetes virtual machines (`k8s-cp-01`, `k8s-telemetry-01`, `k8s-app-01`) received the identical dynamic DHCP IP lease from the local router.
* **Root Cause:** Systemd-networkd generates DHCP client identifiers (DUID) directly from `/etc/machine-id`. Because golden template 9000 was created without truncating `/etc/machine-id`, all cloned VMs sent the identical DUID in their DHCP solicitations.
* **Resolution:** Truncated `/etc/machine-id` using `virt-customize -a noble-server-cloudimg-amd64.img --install qemu-guest-agent --truncate /etc/machine-id` during the golden template creation workflow, and regenerated unique IDs on active VMs via `systemd-machine-id-setup`.

### 2. Kubernetes NodeRestriction Admission Plugin Enforcement (Cluster Security Layer)

* **Symptom:** Worker nodes joined the cluster with `<none>` roles, ignoring self-assigned `--node-labels node-role.kubernetes.io/<role>=true` flags passed to the k3s agent join script.
* **Root Cause:** The Kubernetes `NodeRestriction` admission controller strictly prohibits kubelets from self-assigning or modifying labels within the `node-role.kubernetes.io/` namespace during join.
* **Resolution:** Removed `--node-role` and label flags from `bootstrap/02-k3s-agent.sh` (preserving it as a pure join mechanism), and added Play 3 to `ansible/playbooks/04-bootstrap-cluster.yml` to apply node roles directly from `k8s-cp-01` via `kubectl label node`.

### 3. Cilium Helm / Kubernetes API Schema Typecast Collision (Platform/CNI Layer)

* **Symptom:** `cilium install` failed during rollout with `Deployment in version "v1" cannot be handled as a Deployment: json: cannot unmarshal bool into Go struct field PodSpec.spec.template.spec.nodeSelector of type string`.
* **Root Cause:** Passing `--set "hubble.relay.nodeSelector.node-role\.kubernetes\.io/telemetry=true"` caused Helm to type-cast `true` into a YAML boolean instead of a string, violating the Kubernetes API schema for `PodSpec.nodeSelector` (`map[string]string`).
* **Resolution:** Refactored the selector in `bootstrap/03-cni-cilium.sh` to `workload=telemetry`, providing a string value that bypasses Helm boolean type coercion and aligns with the cluster workload profile convention.

## Verification

??? note "Cluster Nodes & Role Verification (`kubectl get nodes`)"
    ```text
    NAME               STATUS   ROLES           AGE   VERSION
    k8s-app-01         Ready    app             60m   v1.37.2+k3s1
    k8s-cp-01          Ready    control-plane   60m   v1.37.2+k3s1
    k8s-telemetry-01   Ready    telemetry       60m   v1.37.2+k3s1
    ```

??? note "Core Platform Services Pods Status (`kubectl get pods -A`)"
    ```text
    NAMESPACE     NAME                                                    READY   STATUS    RESTARTS   AGE
    argocd        argocd-application-controller-0                         1/1     Running   0          8m
    argocd        argocd-applicationset-controller-b764968bf-jlgtx        1/1     Running   0          8m
    argocd        argocd-dex-server-5d7f54495d-jxsdn                      1/1     Running   0          2m
    argocd        argocd-notifications-controller-79766d8cbf-4xxhg        1/1     Running   0          8m
    argocd        argocd-redis-9bfb7b976-xjs8n                            1/1     Running   0          8m
    argocd        argocd-repo-server-555f8b597f-6kc64                     1/1     Running   0          8m
    argocd        argocd-server-76c54c4c57-wgsrb                          1/1     Running   0          8m
    chaos-mesh    chaos-controller-manager-54cb7bfdbc-4qffx               1/1     Running   0          7m
    chaos-mesh    chaos-daemon-htpgj                                      1/1     Running   0          7m
    chaos-mesh    chaos-dashboard-75747bb9d6-w5x59                        1/1     Running   0          7m
    kube-system   cilium-72m5c                                            1/1     Running   0          11m
    kube-system   cilium-operator-6698c97cf4-wxh7l                        1/1     Running   0          11m
    ```
