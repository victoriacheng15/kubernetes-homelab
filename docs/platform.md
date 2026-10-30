# Observability & Security

## Overview

This document details the telemetry, runtime security, and policy enforcement stack running on the cluster.

## Metrics Pipeline (Prometheus)

<!-- Telemetry collection configuration and architecture -->

## Distributed Tracing (OpenTelemetry)

<!-- Tracing pipeline configuration -->

## Visualization & Dashboards (Grafana)

??? note "Screenshot: Grafana Cluster Overview Dashboard"
    *Cluster CPU/memory saturation, node health, and pod metrics visualization.*

    <!-- Screenshot Path: docs/assets/screenshots/grafana-cluster-overview.png -->

## Network Policies & Traffic Flows (Cilium & Hubble)

??? note "Screenshot / Demo: Hubble UI Service Map & Flow Inspection"
    *Real-time L3/L4/L7 service dependencies, packet drops, and HTTP flow tracking.*

    <!-- Image: docs/assets/screenshots/hubble-ui-flows.png -->
    <!-- Video: docs/assets/demos/hubble-traffic-inspection.mp4 -->

## Admission Control & Policies (Kyverno)

<!-- Policy enforcement configuration -->

## Kernel Runtime Security (Falco)

??? note "Screenshot: Falco Kernel Event Alerts"
    *Real-time behavioral threat detection stream (e.g., terminal shell spawned inside workload pod).*

    <!-- Screenshot Path: docs/assets/screenshots/falco-runtime-alerts.png -->

## Chaos & Vulnerability Testing (Chaos Mesh & OWASP Juice Shop)

<!-- Chaos Mesh experiment and vulnerability testing scenarios -->
