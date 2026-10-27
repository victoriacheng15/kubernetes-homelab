# /// script
# dependencies = [
#     "diagrams",
# ]
# ///

from diagrams import Cluster, Diagram, Edge
from diagrams.k8s.compute import Pod
from diagrams.k8s.controlplane import API
from diagrams.k8s.storage import PV
from diagrams.onprem.compute import Server
from diagrams.onprem.container import LXC
from diagrams.onprem.gitops import Argocd
from diagrams.onprem.iac import Ansible, Terraform
from diagrams.onprem.monitoring import Grafana, Prometheus
from diagrams.onprem.vcs import Git

# ==============================================================================
# Unified Design Tokens & Global Styles
# ==============================================================================

FONT_FAMILY = "Helvetica Neue, Helvetica, Arial, sans-serif"
COLOR_CANVAS = "#f8fafc"  # Slate 50
COLOR_TEXT = "#0f172a"    # Slate 900
COLOR_LINE = "#64748b"    # Slate 500
COLOR_BORDER = "#64748b"  # Slate 500
COLOR_MUTED_BORDER = "#94a3b8"  # Slate 400

base_graph_attr = {
    "fontsize": "26",
    "fontname": FONT_FAMILY,
    "pad": "0.6",
    "splines": "ortho",
    "nodesep": "0.8",
    "ranksep": "1.0",
    "bgcolor": COLOR_CANVAS,
    "fontcolor": COLOR_TEXT,
}

common_node_attr = {
    "fontsize": "16",
    "fontname": FONT_FAMILY,
    "labelloc": "b",
    "imagepos": "tc",
    "fontcolor": COLOR_TEXT,
}

common_edge_attr = {
    "fontsize": "16",
    "fontname": FONT_FAMILY,
    "color": COLOR_LINE,
}

cluster_outer_attr = {
    "bgcolor": "#f1f5f9",  # Slate 100
    "pencolor": COLOR_BORDER,
    "penwidth": "2.0",
    "fontcolor": COLOR_TEXT,
    "fontsize": "18",
    "fontname": FONT_FAMILY,
    "margin": "25",
}

cluster_inner_attr = {
    "bgcolor": "#e2e8f0",  # Slate 200
    "pencolor": COLOR_MUTED_BORDER,
    "penwidth": "2.0",
    "fontcolor": COLOR_TEXT,
    "fontsize": "18",
    "fontname": FONT_FAMILY,
    "margin": "25",
}

# ==============================================================================
# Diagram 1: Platform Architecture Layers (3-Tier Nested Stack)
# ==============================================================================

with Diagram(
    "Platform Architecture Layers",
    show=False,
    direction="LR",
    curvestyle="ortho",
    graph_attr=base_graph_attr,
    node_attr=common_node_attr,
    edge_attr=common_edge_attr,
    filename="docs/assets/platform-layers",
    outformat="png",
):
    with Cluster("Layer 1: Infrastructure Provisioning", graph_attr=cluster_outer_attr):
        tofu = Terraform("OpenTofu\n(IaaS)")
        pve = Server("Proxmox VE\n(VMs & LXCs)")
        tofu >> Edge(color="#2563eb", penwidth="1.8", label="provisions") >> pve

        with Cluster("Layer 2: Configuration Management", graph_attr=cluster_inner_attr):
            ansible = Ansible("Ansible\n(Automation)")
            os_tune = Server("OS Baseline\n(sysctl, swap, pkgs)")
            ansible >> Edge(color="#10b981", penwidth="1.8", label="configures") >> os_tune

            with Cluster("Layer 3: Declarative GitOps", graph_attr=cluster_outer_attr):
                argo = Argocd("ArgoCD")
                k8s = Pod("Kubernetes")
                argo >> Edge(color="#f97316", penwidth="1.8", label="reconciles") >> k8s

        pve >> Edge(color="#64748b", penwidth="2.2", style="bold", label="Hardware Ready") >> ansible
        os_tune >> Edge(color="#64748b", penwidth="2.2", style="bold", label="Nodes Ready") >> argo

# ==============================================================================
# Diagram 2: Physical Topology & Quorum
# ==============================================================================

with Diagram(
    "Physical Topology",
    show=False,
    direction="LR",
    curvestyle="ortho",
    graph_attr=base_graph_attr,
    node_attr=common_node_attr,
    edge_attr=common_edge_attr,
    filename="docs/assets/physical-topology",
    outformat="png",
):
    with Cluster("Home LAN", graph_attr=cluster_outer_attr):
        with Cluster("Proxmox VE Cluster", graph_attr=cluster_inner_attr):
            pve01 = Server("pve-01")
            pve02 = Server("pve-02")

        with Cluster("rpi-01", graph_attr=cluster_inner_attr):
            qdevice = Server("Corosync QDevice")
            ntp = Server("Chrony NTP (UTC)")

        # Corosync Quorum & Witness Links
        pve01 - Edge(color="#2563eb", penwidth="2.5", label="Corosync") - pve02
        qdevice >> Edge(color="#10b981", style="dashed", penwidth="2.0") >> pve01
        qdevice >> Edge(color="#10b981", style="dashed", penwidth="2.0") >> pve02
        ntp >> Edge(color="#f97316", style="dashed", penwidth="2.0") >> pve01
        ntp >> Edge(color="#f97316", style="dashed", penwidth="2.0") >> pve02

# ==============================================================================
# Diagram 3: Kubernetes Homelab Architecture
# ==============================================================================

with Diagram(
    "Kubernetes Homelab Architecture",
    show=False,
    direction="TB",
    curvestyle="ortho",
    graph_attr=base_graph_attr,
    node_attr=common_node_attr,
    edge_attr=common_edge_attr,
    filename="docs/assets/architecture",
    outformat="png",
):
    with Cluster("Home LAN", graph_attr=cluster_outer_attr):
        with Cluster("Physical Host: pve-01 (Mini PC)", graph_attr=cluster_inner_attr):
            with Cluster("k8s-cp-01 (Control Plane)", graph_attr=cluster_outer_attr):
                cilium_cp = Pod("Cilium CNI")
                cp_api = API("k3s API Server")
                cp_storage = PV("Embedded etcd")

                cilium_cp >> Edge(style="invis") >> cp_api
                cp_api - cp_storage

            with Cluster("k8s-telemetry-01 (Telemetry Node)", graph_attr=cluster_outer_attr):
                hubble = Pod("Cilium Hubble")
                argocd = Argocd("ArgoCD")
                otel = Pod("OTel Collector")
                prom = Prometheus("Prometheus")
                grafana = Grafana("Grafana")

                hubble >> Edge(style="invis") >> otel
                hubble >> Edge(style="invis") >> argocd
                otel >> prom
                prom >> grafana

            with Cluster("LXC Utilities", graph_attr=cluster_outer_attr):
                tailscale = LXC("Tailscale")
                nginx = LXC("Nginx")
                ansible = LXC("Ansible")

                tailscale >> Edge(style="invis") >> nginx >> Edge(style="invis") >> ansible

        with Cluster("Physical Host: pve-02 (Laptop)", graph_attr=cluster_inner_attr):
            with Cluster("k8s-app-01 (App Node)", graph_attr=cluster_outer_attr):
                cilium_app = Pod("Cilium CNI")
                chaos = Pod("Chaos Mesh")
                podinfo = Pod("Podinfo")
                juice = Pod("OWASP Juice Shop")
                falco = Pod("Falco")

                cilium_app >> Edge(style="invis") >> chaos
                cilium_app >> Edge(style="invis") >> juice
                chaos - Edge(color="#64748b") - podinfo
                juice - Edge(color="#64748b") - falco

            with Cluster("LXC Utilities", graph_attr=cluster_outer_attr):
                pihole = LXC("Pi-hole")


# ==============================================================================
# Diagram 4: GitOps Flow
# ==============================================================================

with Diagram(
    "GitOps Flow",
    show=False,
    direction="LR",
    curvestyle="ortho",
    graph_attr=base_graph_attr,
    node_attr=common_node_attr,
    edge_attr=common_edge_attr,
    filename="docs/assets/gitops",
    outformat="png",
):
    with Cluster("Source Control", graph_attr=cluster_outer_attr):
        git = Git("Git Repository")

    with Cluster("Continuous Delivery", graph_attr=cluster_outer_attr):
        argocd = Argocd("ArgoCD")

    with Cluster("Applications", graph_attr=cluster_outer_attr):
        podinfo = Pod("Podinfo")
        juice = Pod("OWASP Juice Shop")

    with Cluster("Security & Chaos", graph_attr=cluster_outer_attr):
        chaos = Pod("Chaos Mesh")
        falco = Pod("Falco")

    with Cluster("Observability", graph_attr=cluster_outer_attr):
        prom = Prometheus("Prometheus")
        otel = Pod("OTel Collector")

    with Cluster("Dashboards", graph_attr=cluster_outer_attr):
        grafana = Grafana("Grafana")

    # GitOps deployment flow
    git >> Edge(color="#d97706", penwidth="2.0") >> argocd
    argocd >> Edge(color="#3182ce", penwidth="1.8") >> podinfo
    argocd >> Edge(color="#3182ce", penwidth="1.8") >> juice
    argocd >> Edge(color="#3182ce", penwidth="1.8") >> prom
    argocd >> Edge(color="#3182ce", penwidth="1.8") >> otel
    argocd >> Edge(color="#3182ce", penwidth="1.8") >> grafana
    argocd >> Edge(color="#3182ce", penwidth="1.8") >> chaos
    argocd >> Edge(color="#3182ce", penwidth="1.8") >> falco

    # Chaos failure injection & Security monitoring
    chaos >> Edge(style="invis") >> podinfo
    chaos >> Edge(style="invis") >> juice
    falco - Edge(style="invis") - juice
    falco >> Edge(style="invis") >> prom
    falco >> Edge(style="invis") >> otel

    # Applications telemetry stream to Observability
    podinfo >> Edge(style="invis") >> prom
    juice >> Edge(style="invis") >> prom

    # Observability metrics query into Dashboards
    prom >> Edge(style="invis") >> grafana



