# Cluster Operations & GitOps

## Overview

This guide covers the operational lifecycle of the homelab, focusing on Kubernetes cluster bootstrapping, network fabric deployment, and declarative GitOps workload reconciliation.

Physical hypervisor clustering, OpenTofu IaaS provisioning, and Ansible OS baseline configuration are documented separately in the one-time [Infrastructure & OS Provisioning Guide](./provisioning.md).

---

## Prerequisites

Before proceeding with cluster bootstrapping, ensure that:

1. Physical hosts, VMs, and utility containers are provisioned via OpenTofu (see [Layer 1 Provisioning](./provisioning.md#layer-1-infrastructure-provisioning-opentofu--proxmox)).
2. Kernel modules, swap disablement, and sysctl network parameters are applied across all VMs via Ansible (see [Layer 2 Provisioning](./provisioning.md#layer-2-node-os-baseline-provisioning-ansible)).

---

## Cluster Bootstrap

### Control Plane Provisioning (k3s Server)

### CNI Deployment (Cilium eBPF)

### Agent & Worker Joins

## GitOps & Workloads

### ArgoCD App-of-Apps Engine

### Secrets Management

### Application Deployments
