# ADR 006: Orchestrated Cluster Bootstrap via Ansible Scripts

- **Status:** Proposed
- **Date:** 2026-11-04
- **Author:** Victoria Cheng

## Context and Problem Statement

Bootstrapping a multi-node Kubernetes cluster requires tightly sequenced Day-1 operations: initializing the k3s control plane, retrieving the cluster join token, joining worker nodes with dedicated workload labels, deploying the Cilium eBPF network fabric, and installing the ArgoCD GitOps engine.

Executing these steps manually via individual SSH sessions is error-prone, difficult to audit, and directly opposes the goal of running zero-touch disaster recovery drills ("The Phoenix Rebuild").

Several architectural approaches introduce friction and severe trade-offs:

- **Inline Shell Scripting in YAML (`ansible.builtin.shell`):** Embedding raw multiline bash scripts directly inside YAML tasks creates unreadable "YAML soup". It complicates variable escaping, prevents static analysis with tools like `shellcheck`, breaks syntax highlighting, and makes scripts impossible to test standalone.
- **Complete Rewrite into Native Ansible Modules:** Translating procedural cluster initialization and release-detection scripts into dozens of declarative YAML tasks creates brittle state parsing, slow execution loops, and bloated maintenance overhead.
- **Per-Node Manual Execution:** Manually transferring scripts, logging into individual VM consoles, and copying tokens between nodes by hand is slow, error-prone, and impossible to automate for clean-slate disaster recovery.
- **Single SSH Key Blast Radius:** Using the human administrator's personal SSH key for automated Ansible execution exposes broad administrative privileges if the automation controller container is compromised.

How should the cluster bootstrap pipeline be orchestrated to achieve rapid, reproducible disaster recovery while keeping nodes stateless and scripts modular?

## Decision Outcome

Implement an orchestrated hybrid bootstrap architecture combining Ansible plays with standalone idempotent shell scripts, accompanied by a dual-key SSH model:

### Wrap Rather Than Rewrite (`ansible.builtin.script`)

- Preserve clean, standalone bash scripts under `bootstrap/` (`01-k3s-server.sh`, `02-k3s-agent.sh`, `03-cni-cilium.sh`, `04-gitops-argocd.sh`, `05-chaos-mesh.sh`). Standalone scripts retain syntax highlighting, direct linting with `shellcheck`, and local testing capabilities (`--dry-run`, `--version`).
- Orchestrate script execution remotely using Ansible's `ansible.builtin.script` module. Ansible transfers the script temporarily to the target VM over SSH, executes it with the required arguments, and deletes the temporary binary.

### Numbered Sequential Pipeline

Structure all automation playbooks into sequential numbered stages under `ansible/playbooks/`:

- `01-setup-vms.yml`: Base OS tuning, swap disabling, kernel modules, and sysctl rules.
- `02-setup-pihole.yml`: Local wildcard DNS sinkhole (`*.homelab.local`).
- `03-setup-tailscale.yml`: Encrypted mesh VPN subnet router.
- `04-bootstrap-cluster.yml`: Control plane initialization, in-memory token distribution, and worker node onboarding.
- `05-setup-cluster-services.yml`: In-cluster Cilium eBPF CNI, ArgoCD continuous delivery engine, and Chaos Mesh platform.
- `06-setup-nginx.yml`: Ingress gateway virtual host routing for all `*.homelab.local` endpoints.

A root orchestrator playbook (`ansible/site.yml`) imports all six numbered stages in order for single-command end-to-end execution.

### In-Memory Token Distribution

- The control plane play executes `01-k3s-server.sh` and slurps `/var/lib/rancher/k3s/server/node-token`.
- The token is registered in Ansible memory (`set_fact: k3s_token`) and passed directly into worker join commands (`02-k3s-agent.sh`), eliminating manual token copying.

### Dual-Key SSH Architecture

- Establish two distinct Ed25519 SSH keys:
  - Administrator Key (`k8s-homelab-admin`): For interactive operator access and direct debugging.
  - Automation Key (`ansible`): Stored exclusively on `CT 303` for automated playbook runs.
- OpenTofu Cloud-Init and LXC user account provisioning inject both public keys on first boot.

## Consequences

### Positive

- **Zero-Touch Disaster Recovery:** The entire infrastructure from bare OS baseline to reverse proxy ingress can be reconstructed with a single command (`ansible-playbook -i inventory.ini site.yml`).
- **Centralized Orchestration:** Automation executes outward from a single controller without requiring manual node coordination or transferring files by hand.
- **Modularity:** Scripts remain independently executable for debugging via standard bash flags (`--dry-run`, `--version`).
- **Reduced Blast Radius:** The automation controller key is isolated from personal workstation credentials, simplifying rotation and auditing in `journalctl -u ssh`.

### Negative

- **Default Changed Status:** Ansible's `script` module defaults to `changed: true` upon exit code 0 because it cannot introspect internal bash commands without explicit `changed_when` rules.
- **Explicit Context Requirements:** In-cluster CLI tools (`cilium`, `helm`, `kubectl`) invoked via `ansible.builtin.script` require explicit injection of `KUBECONFIG: /etc/rancher/k3s/k3s.yaml` when running under `sudo`/`become: true`.

## Verification

- [ ] **Cluster Node Joining:** Verify `04-bootstrap-cluster.yml` initializes `k8s-cp-01` and joins `k8s-telemetry-01` and `k8s-app-01` cleanly.
- [ ] **Platform Services Bootstrap:** Verify `05-setup-cluster-services.yml` deploys Cilium, ArgoCD, and Chaos Mesh, with all pods reaching `Running` status.
- [ ] **Gateway Routing:** Verify `06-setup-nginx.yml` configures virtual host routes and enables access across all `*.homelab.local` endpoints.
- [ ] **Full Pipeline Drill:** Execute the complete Phoenix Rebuild from bare VMs through `site.yml` end to end to confirm zero-touch reproducibility.
