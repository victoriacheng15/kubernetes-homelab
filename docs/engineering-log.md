# Engineering Log

Chronological record of physical hardware provisioning, cluster state transitions, operational debugging, and verification outputs.

---

## 2026-10-25 - Physical Clustering, Corosync Quorum, and OpenTofu Provisioning

### Summary

Initialized the physical dual-node Proxmox VE cluster (`k8s-homelab`) with an external Raspberry Pi Corosync QDevice tiebreaker, achieving an odd 3-vote quorum ($N=3$). Configured Stratum 2 Chrony NTP on `rpi-01`, aligned existing utility containers, and automated VM and LXC deployment using OpenTofu.

### Target Nodes & Scope

* **Physical Hosts:** `pve-01` (Mini PC), `pve-02` (Laptop), `rpi-01` (Raspberry Pi 4)
* **Virtual Machines:** `k8s-cp-01` (VM 100), `k8s-telemetry-01` (VM 101), `k8s-app-01` (VM 200), Ubuntu 24.04 Template (VM 9000)
* **Containers (LXC):** `pihole` (CT 300 on `pve-02`), `tailscale` (CT 301 on `pve-01`), `nginx` (CT 302 on `pve-01`), `ansible` (CT 303 on `pve-01`)

### Actions Executed

* Formed the Proxmox cluster `k8s-homelab` on `pve-01` and joined `pve-02`.
* Preserved existing container configs across the `pmxcfs` join and migrated `tailscale` (CT 301) from `pve-02` to `pve-01`.
* Installed `corosync-qnetd` on `rpi-01` and attached it as the external cluster QDevice via `pvecm qdevice setup`.
* Configured Chrony NTP on `rpi-01` as the local network time server and synchronized `pve-01` and `pve-02`.
* Migrated Ubuntu 24.04 Cloud-Init template (VM 9000) to `pve-01` local storage.
* Downloaded Debian 13 standard amd64 LXC template on `pve-01`.
* Configured OpenTofu manifests (`infra/`) to provision Kubernetes VMs and manage LXC utility containers.

### Verification & Terminal Outputs

#### 1. Cluster Quorum & QDevice Status (`pvecm status`)

```text
Cluster information
-------------------
Name:             k8s-homelab
Config Version:   3
Transport:        knet
Secure auth:      on

Quorum information
------------------
Date:             Mon Oct 26 02:13:26 2026
Quorum provider:  corosync_votequorum
Nodes:            2
Node ID:          0x00000001
Ring ID:          1.1b
Quorate:          Yes

Votequorum information
----------------------
Expected votes:   3
Highest expected: 3
Total votes:      3
Quorum:           2  
Flags:            Quorate Qdevice 

Membership information
----------------------
    Nodeid      Votes    Qdevice Name
         1          1    A,V,NMW pve-01 (local)
         2          1    A,V,NMW pve-02
         0          1            Qdevice
```

#### 2. Authoritative Time Synchronization (`chronyc sources -v`)

```text
MS Name/IP address         Stratum Poll Reach LastRx Last sample               
===============================================================================
^- time.cloudflare.com           3   6    17     7   +462us[ +462us] +/-   24ms
^* time4.google.com              1   6    17     7   +142us[ +676us] +/-   10ms
^- archer.fsck.ca                2   6    17     6   -572us[ -572us] +/-   36ms
```

### Incidents, Root Causes & Fixes

* **Issue 1: Proxmox Join Blocked Due to Pre-existing Containers**
  * **Symptom:** `pvecm add` failed with error: `this host already contains virtual guests`.
  * **Root Cause:** Joining a cluster mounts the shared `pmxcfs` cluster filesystem over `/etc/pve`, which would hide local guest configurations if not preserved.
  * **Fix:** Backed up `/etc/pve/local/lxc` to `/root/pve-lxc-backup`, executed `pvecm add <PVE_01_IP> --force`, and restored `.conf` files into `/etc/pve/nodes/pve-02/lxc/`.

* **Issue 2: Proxmox API HTTP 403 Forbidden on VM Clone**
  * **Symptom:** OpenTofu returned: `error cloning VM: received an HTTP 403 response - Reason: Permission check failed (/vms/9000, VM.Clone)`.
  * **Root Cause:** Proxmox Web GUI checks **Privilege Separation** by default when creating API tokens, stripping administrative permissions from `root@pam!tofu`.
  * **Fix:** Recreated the token with **Privilege Separation unchecked**, restoring inherited root permissions.

* **Issue 3: OpenTofu Failed to Locate Template 9000 on `pve-02`**
  * **Symptom:** OpenTofu returned: `HTTP 500 - unable to find configuration file for VM 9000 on node 'pve-02'`.
  * **Root Cause:** Template 9000 resides on `pve-01`. When provisioning `k8s-app-01` on `pve-02`, OpenTofu defaulted to searching for the template on the target node.
  * **Fix:** Added `node_name = "pve-01"` explicitly inside the `clone` block in `infra/02-vms.tf`.

* **Issue 4: QDevice Marked as `NR` for `pve-02`**
  * **Symptom:** `pvecm nodes` displayed `NR` under the Qdevice column for `pve-02`, causing OpenTofu plan timeouts.
  * **Root Cause:** `NR` signifies "Not Registered" with the remote `corosync-qnetd` daemon. After simulated failover testing, `corosync-qdevice.service` was stopped on `pve-02`.
  * **Fix:** Executed `systemctl restart corosync-qdevice` on `pve-02`, successfully reconnecting to port 5403 on `rpi-01`.
