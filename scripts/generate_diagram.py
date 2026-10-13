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
        with Cluster("k8s-cp-01 (Control Plane)", graph_attr=inner_box_attr):
            cp_api = API("k3s API Server")
            cp_storage = PV("Embedded etcd")
            cilium_cp = Server("Cilium CNI")
            cp_api - cp_storage

        with Cluster("k8s-telemetry-01 (Telemetry Node)", graph_attr=inner_box_attr):
            argocd = Argocd("ArgoCD")
            otel = Server("OTel Collector")
            prom = Prometheus("Prometheus")
            grafana = Grafana("Grafana")
            hubble = Server("Cillium Hubble")

            otel >> prom
            prom >> grafana

    with Cluster("Physical Box 2: pve-02", graph_attr=box_attr):
        with Cluster("k8s-app-01 (App Node)", graph_attr=inner_box_attr):
            podinfo = Pod("Podinfo")
            chaos = Server("Chaos Mesh")
            juice = Server("OWASP Juice Shop")
            falco = Server("Falco")
            cilium_app = Server("Cilium CNI")

            # chaos >> Edge(style="dashed", color="#e53e3e") >> podinfo
            # chaos >> Edge(style="dashed", color="#e53e3e") >> juice
            falco - juice

    with Cluster("Physical Box 3: rpi-01", graph_attr=box_attr):
        with Cluster("rpi-01", graph_attr=inner_box_attr):
            rpi = Server("pi")

    # Home LAN network connections directly to the physical box wrappers
    lan >> Edge(color="#3182ce") >> cp_api
    lan >> Edge(color="#3182ce") >> podinfo
    lan >> Edge(color="#3182ce") >> rpi

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
        juice = Server("OWASP Juice Shop")

    with Cluster("Security & Chaos", graph_attr=box_attr):
        chaos = Server("Chaos Mesh")
        falco = Server("Falco")

    with Cluster("Observability", graph_attr=box_attr):
        prom = Prometheus("Prometheus")
        otel = Server("OTel Collector")

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
