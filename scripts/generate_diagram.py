# /// script
# dependencies = [
#     "diagrams",
# ]
# ///

from diagrams import Diagram, Cluster, Edge
from diagrams.onprem.compute import Server
from diagrams.onprem.network import Internet
from diagrams.onprem.vcs import Git
from diagrams.k8s.controlplane import API, Kubelet
from diagrams.k8s.compute import Pod
from diagrams.k8s.storage import PV
from diagrams.onprem.monitoring import Prometheus, Grafana
from diagrams.onprem.gitops import Argocd
from diagrams.onprem.container import LXC

graph_attr = {
    "fontsize": "20",
    "pad": "0.5",
    "splines": "polyline",
    "nodesep": "1.0",
    "ranksep": "1.5",
}

node_attr = {
    "fontsize": "12",
    "labelloc": "b",
    "imagepos": "tc",
}

edge_attr = {
    "fontsize": "12",
    "color": "#718096",
}

box_attr = {
    "bgcolor": "#f7fafc",
    "pencolor": "#4a5568",
    "margin": "18",
}

inner_box_attr = {
    "bgcolor": "#edf2f7",
    "pencolor": "#cbd5e0",
    "margin": "20",
}

with Diagram(
    "Kubernetes Homelab Architecture",
    show=False,
    direction="TB",
    graph_attr=graph_attr,
    node_attr=node_attr,
    edge_attr=edge_attr,
    filename="docs/assets/architecture",
    outformat="png",
):
    lan = Internet("Home LAN")

    with Cluster("Physical Box 1: pve-01", graph_attr=box_attr):
        pve01 = Server("pve-01")

        with Cluster("k8s-cp-01 (Control Plane)", graph_attr=inner_box_attr):
            cp_api = API("k3s API Server")
            cp_storage = PV("Embedded etcd")
            cilium_cp = Pod("Cilium CNI")
            cp_api - cp_storage

        with Cluster("k8s-telemetry-01 (Telemetry Node)", graph_attr=inner_box_attr):
            argocd = Argocd("ArgoCD")
            otel = Pod("OTel Collector")
            prom = Prometheus("Prometheus")
            grafana = Grafana("Grafana")
            hubble = Pod("Cilium Hubble")

            otel >> prom
            prom >> grafana

        with Cluster("LXC", graph_attr=inner_box_attr):
            tailscale = LXC("Tailscale (CT 301)")
            nginx = LXC("Nginx (CT 302)")

    with Cluster("Physical Box 2: pve-02", graph_attr=box_attr):
        pve02 = Server("pve-02")

        with Cluster("k8s-app-01 (App Node)", graph_attr=inner_box_attr):
            podinfo = Pod("Podinfo")
            chaos = Pod("Chaos Mesh")
            juice = Pod("OWASP Juice Shop")
            falco = Pod("Falco")
            cilium_app = Pod("Cilium CNI")

            chaos - podinfo
            falco - juice

        with Cluster("LXC", graph_attr=inner_box_attr):
            pihole = LXC("Pi-hole (CT 300)")

    with Cluster("Physical Box 3: rpi-01", graph_attr=box_attr):
        rpi01 = Server("rpi-01")

        with Cluster("Infrastructure Services", graph_attr=inner_box_attr):
            qdevice = Server("Corosync QDevice")
            ntp = Server("Chrony NTP (UTC)")

    # Home LAN network connections directly to the physical hosts & network services
    lan >> Edge(color="#3182ce") >> pve01
    lan >> Edge(color="#3182ce") >> pve02
    lan >> Edge(color="#3182ce") >> rpi01

    # Host-to-guest hierarchy (forces physical hosts to sit cleanly above inner services)
    pve01 >> Edge(style="invis") >> cp_api
    pve02 >> Edge(style="invis") >> podinfo
    rpi01 >> Edge(style="invis") >> qdevice

    # Time synchronization
    ntp >> Edge(color="#805ad5", style="dashed", penwidth="2.0") >> pve01
    ntp >> Edge(color="#805ad5", style="dashed", penwidth="2.0") >> pve02

graph_attr_gitops = {
    **graph_attr,
    "splines": "polyline",
    "nodesep": "1.0",
    "ranksep": "1.5",
}

with Diagram(
    "GitOps Flow",
    show=False,
    direction="LR",
    graph_attr=graph_attr_gitops,
    node_attr=node_attr,
    edge_attr=edge_attr,
    filename="docs/assets/gitops-flow",
    outformat="png",
):
    git = Git("Git Repository")
    argocd = Argocd("ArgoCD")

    with Cluster("Applications", graph_attr=box_attr):
        podinfo = Pod("Podinfo")
        juice = Pod("OWASP Juice Shop")

    with Cluster("Security & Chaos", graph_attr=box_attr):
        chaos = Pod("Chaos Mesh")
        falco = Pod("Falco")

    with Cluster("Observability", graph_attr=box_attr):
        prom = Prometheus("Prometheus")
        otel = Pod("OTel Collector")

    with Cluster("Dashboards", graph_attr=box_attr):
        grafana = Grafana("Grafana")

    # GitOps deployment flow
    git >> Edge(color="#d97706") >> argocd
    argocd >> Edge(color="#3182ce") >> podinfo
    argocd >> Edge(color="#3182ce") >> juice
    argocd >> Edge(color="#3182ce") >> prom
    argocd >> Edge(color="#3182ce") >> grafana
    argocd >> Edge(color="#3182ce") >> chaos
    argocd >> Edge(color="#3182ce") >> falco

    # Chaos failure injection & Security monitoring
    chaos >> Edge(style="dashed", color="#e53e3e") >> podinfo
    chaos >> Edge(style="dashed", color="#e53e3e") >> juice
    falco - Edge(color="#718096") - juice
    falco >> Edge(color="#38a169") >> prom

    # Applications telemetry stream to Observability
    podinfo >> Edge(color="#38a169") >> prom
    podinfo >> Edge(color="#3182ce") >> otel
    juice >> Edge(color="#38a169") >> prom

    # Observability metrics query into Dashboards
    prom >> Edge(color="#4a5568") >> grafana
