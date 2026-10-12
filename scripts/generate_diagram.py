# /// script
# dependencies = [
#     "diagrams",
# ]
# ///

from diagrams import Diagram, Cluster, Edge
from diagrams.onprem.compute import Server
from diagrams.onprem.network import Internet
from diagrams.k8s.controlplane import API, Kubelet
from diagrams.k8s.storage import PV
from diagrams.onprem.monitoring import Prometheus, Grafana
from diagrams.onprem.gitops import Argocd

graph_attr = {
    "fontsize": "20",
    "fontname": "Noto Sans",
    "bgcolor": "#ffffff",
    "pad": "0.5",
    "splines": "ortho",
    "nodesep": "1.0",
    "ranksep": "1.2",
}

node_attr = {
    "fontname": "Noto Sans",
    "fontsize": "12",
    "labelloc": "b",
    "imagepos": "tc",
}

edge_attr = {
    "fontname": "Noto Sans",
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

    with Cluster("Physical Box 1: pve-01", graph_attr=box_attr) as box1:
        with Cluster("k8s-cp-01 (Control Plane)", graph_attr=inner_box_attr):
            cp_api = API("k3s API Server")
            cp_storage = PV("Embedded etcd")
            cilium_cp = Server("Cilium CNI\n(eBPF)")
            cp_api - cp_storage
            cp_api - cilium_cp

        with Cluster("k8s-telemetry-01 (Telemetry Node)", graph_attr=inner_box_attr):
            argocd = Argocd("ArgoCD")
            otel = Server("OTel Collector")
            prom = Prometheus("Prometheus")
            grafana = Grafana("Grafana")
            hubble = Server("Hubble Relay\n& UI (Cilium)")

            otel >> Edge(color="#4a5568") >> prom
            prom >> Edge(color="#4a5568") >> grafana
            otel >> Edge(color="#4a5568") >> grafana
            hubble >> Edge(color="#4a5568") >> grafana

    with Cluster("Physical Box 2: pve-02", graph_attr=box_attr) as box2:
        with Cluster("k8s-app-01 (App Node)", graph_attr=inner_box_attr):
            go_app = Server("Go OTel App")
            chaos = Server("Chaos Mesh")
            juice = Server("OWASP Juice Shop")
            falco = Server("Falco")
            cilium_app = Server("Cilium CNI\n(eBPF)")

            go_app >> Edge(label="OTLP", color="#3182ce") >> otel
            chaos >> Edge(label="Chaos", style="dashed", color="#e53e3e") >> go_app
            juice - Edge(color="#718096") - falco
            cilium_app >> Edge(label="eBPF flows", color="#38a169") >> hubble

    with Cluster("Physical Box 3: rpi-01", graph_attr=box_attr) as box3:
        with Cluster("rpi-01", graph_attr=inner_box_attr):
            rpi = Server("pi")

    # Home LAN network connections directly to the physical box wrappers
    lan >> Edge(color="#4a5568", lhead=box1.dot.name) >> cp_api
    lan >> Edge(color="#4a5568", lhead=box2.dot.name) >> go_app
    lan >> Edge(color="#4a5568", lhead=box3.dot.name) >> rpi
