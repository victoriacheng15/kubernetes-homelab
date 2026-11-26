# ADR 010: GitOps Sync-Wave Tiering

- **Status:** Proposed
- **Date:** 2026-11-26
- **Author:** Victoria Cheng

## Context and Problem Statement

Deploying all Kubernetes platform controllers, observability pipelines, and workloads as a single flat ArgoCD application introduces dependency race conditions (such as Custom Resources reconciling before their CRDs are registered) and mixes security controllers with application workloads across nodes.

## Decision Outcome

This decision structures GitOps delivery under `gitops/root-application.yaml` using three sequential ArgoCD sync waves with role-based node pinning:

1. **Wave 0 (`gitops/infrastructure/`):** Core platform infrastructure (`cert-manager`, Kyverno, Falco, and `local-path-storage`).
2. **Wave 1 (`gitops/telemetry/`):** Observability and energy telemetry stack (Prometheus, Grafana, OpenTelemetry Collector, and Kepler) pinned to `k8s-telemetry-01`.
3. **Wave 2 (`gitops/apps/`):** Tenant and resilience workloads (two-tier `podinfo-frontend` / `podinfo-backend` and OWASP `juice-shop`).

## Consequences

### Positive

- **Ordered Dependency Reconciliation:** Ensures CRDs, certificates, admission policies, and eBPF runtime security (Wave 0) are active before telemetry (Wave 1) and applications (Wave 2) deploy.
- **Workload & Resource Isolation:** Keeps heavy telemetry ingestion on `k8s-telemetry-01` separate from application workloads (`k8s-app-01`) and protects `k8s-cp-01` stability.

### Negative

- **Sync-Wave Blocking:** A degraded or stuck earlier wave can block downstream waves from reconciling until resolved.

## Verification

- [ ] **Wave 0 Baseline:** Confirm Wave 0 infrastructure (`cert-manager`, `kyverno`, `falco`) reconciles cleanly via ArgoCD.
- [ ] **Wave 1 Telemetry:** Verify Prometheus, Grafana, OpenTelemetry Collector, and Kepler deploy and scrape metrics on `k8s-telemetry-01`.
- [ ] **Wave 2 Applications:** Verify two-tier `podinfo` and `juice-shop` reconcile cleanly in ArgoCD.
