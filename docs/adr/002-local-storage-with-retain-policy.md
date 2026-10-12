# ADR 002: Local Storage with Retain Policy

- **Status:** Proposed
- **Date:** 2026-10-11
- **Author:** Victoria Cheng

## Context and Problem Statement

Persistent storage is required for stateful cluster workloads, including Prometheus TSDB time-series metrics, Grafana dashboard configurations, and ArgoCD application definitions.

Operating persistent storage across only two physical machines (`pve-01` and `pve-02`) introduces critical failure risks:

1. **Replication Split-Brain:** Distributed storage solutions (such as Ceph Rook or Longhorn) require at least 3 nodes with independent storage daemons to establish quorum. With only 2 nodes, network partitions trigger split-brain write locks, read-only degradation, or data corruption.
2. **Network and Drive Overhead:** Replicating storage over consumer Gigabit Ethernet introduces severe I/O write latency and accelerates NVMe drive wear on non-enterprise SSDs.
3. **Data Loss During Reinstalls:** Standard Kubernetes dynamic provisioners default to `reclaimPolicy: Delete`, which deletes underlying persistent volume data whenever a PersistentVolumeClaim (PVC) is removed or a Helm release is redeployed.

How should persistent storage be architected to provide high I/O performance and protect against data loss without split-brain risk in a two-node cluster?

## Decision Outcome

Deploy the `local-path` provisioner with an explicit `reclaimPolicy: Retain`:

1. **Dynamic Local Path Provisioning:**
   - Utilize `local-path-provisioner` to map Kubernetes PersistentVolumes directly to host directories (e.g., `/opt/local-path-provisioner`).
   - Workloads write directly to host storage, bypassing network-based storage abstraction layers.

2. **Strict Reclaim Retention Policy:**
   - Configure the StorageClass with `reclaimPolicy: Retain`.
   - Prevent automatic data destruction when PVCs, namespaces, or Helm charts are deleted or upgraded.

3. **Explicit Rejection of Distributed Storage:**
   - Formally reject Ceph, Longhorn, and GlusterFS for this two-node topology to eliminate quorum-driven storage lockups.

## Consequences

### Positive

- **Native I/O Performance:** Direct host disk mapping delivers bare-metal disk throughput and near-zero latency for write-heavy Prometheus metric ingestion.
- **Zero Split-Brain Risk:** Because storage is not distributed across nodes, network partitions cannot trigger replication locks or data desynchronization.
- **Accidental Deletion Protection:** The `Retain` policy guarantees that underlying persistent files remain on the host filesystem even if Kubernetes objects are deleted.
- **Minimal Resource Footprint:** The provisioner consumes negligible CPU and memory compared to heavy distributed storage control planes.

### Negative

- **Local Node Affinity:** PersistentVolumes are tied to the local node where they were created. A pod requiring an existing volume must run on that same node.
- **Manual Cleanup Required:** Because volumes are retained after PVC deletion, reclaiming disk space requires manual administrator intervention on the host filesystem.
- **Lack of Volume Replication:** Physical hardware disk failure on a host requires restoring from external backups rather than relying on automated cluster disk failover.

## Verification

- [ ] **Manual Check:** Deploy a test pod with a PersistentVolumeClaim using the `local-path` StorageClass and verify it provisions a directory on the host filesystem.
- [ ] **Manual Check:** Delete the PersistentVolumeClaim and verify that the underlying directory on the host disk remains intact with status `Released`.
- [ ] **Manual Check:** Verify StorageClass definition specifies `reclaimPolicy: Retain`.
