# /// script
# dependencies = [
#     "diagrams",
# ]
# ///

from diagrams import Diagram, Cluster, Edge
from diagrams.onprem.compute import Server
from diagrams.onprem.network import Internet
from diagrams.onprem.vcs import Git
from diagrams.k8s.controlplane import API
from diagrams.k8s.compute import Pod
from diagrams.k8s.storage import PV
from diagrams.onprem.monitoring import Prometheus, Grafana
from diagrams.onprem.gitops import Argocd
from diagrams.onprem.container import LXC

graph_attr = {
    "fontsize": "28",
    "fontname": "Helvetica Neue, Helvetica, Arial, sans-serif",
    "pad": "0.6",
    "splines": "ortho",
    "nodesep": "0.8",
    "ranksep": "1.0",
    "bgcolor": "#f8fafc",
    "fontcolor": "#0f172a",
}

node_attr = {
    "fontsize": "18",
    "fontname": "Helvetica Neue, Helvetica, Arial, sans-serif",
    "labelloc": "b",
    "imagepos": "tc",
    "fontcolor": "#0f172a",
}

edge_attr = {
    "fontsize": "14",
    "fontname": "Helvetica Neue, Helvetica, Arial, sans-serif",
    "color": "#64748b",
}

lan_box_attr = {
    "bgcolor": "#edf2f7",
    "pencolor": "#64748b",
    "penwidth": "2.0",
    "fontcolor": "#0f172a",
    "fontsize": "22",
    "fontname": "Helvetica Neue, Helvetica, Arial, sans-serif",
    "margin": "30",
}

host_box_attr = {
    "bgcolor": "#f1f5f9",
    "pencolor": "#64748b",
    "penwidth": "2.0",
    "fontcolor": "#0f172a",
    "fontsize": "19",
    "fontname": "Helvetica Neue, Helvetica, Arial, sans-serif",
    "margin": "30",
}

vm_box_attr = {
    "bgcolor": "#e2e8f0",
    "pencolor": "#94a3b8",
    "penwidth": "2.0",
    "fontcolor": "#0f172a",
    "fontsize": "16",
    "fontname": "Helvetica Neue, Helvetica, Arial, sans-serif",
    "margin": "30",
}

with Diagram(
    "Kubernetes Homelab Architecture",
    show=False,
    direction="TB",
    curvestyle="ortho",
    graph_attr=graph_attr,
    node_attr=node_attr,
    edge_attr=edge_attr,
    filename="docs/assets/architecture",
    outformat="png",
):
    with Cluster("Home LAN", graph_attr=lan_box_attr):
        with Cluster("Physical Host: pve-01 (Mini PC)", graph_attr=host_box_attr):
            pve01 = Server("pve-01")

            with Cluster("k8s-cp-01 (Control Plane)", graph_attr=vm_box_attr):
                cilium_cp = Pod("Cilium CNI")
                cp_api = API("k3s API Server")
                cp_storage = PV("Embedded etcd")

                cilium_cp >> Edge(style="invis") >> cp_api
                cp_api - cp_storage

            with Cluster("k8s-telemetry-01 (Telemetry Node)", graph_attr=vm_box_attr):
                hubble = Pod("Cilium Hubble")
                argocd = Argocd("ArgoCD")
                otel = Pod("OTel Collector")
                prom = Prometheus("Prometheus")
                grafana = Grafana("Grafana")

                hubble >> Edge(style="invis") >> otel
                hubble >> Edge(style="invis") >> argocd
                otel >> prom
                prom >> grafana

            with Cluster("LXC Utilities", graph_attr=vm_box_attr):
                tailscale = LXC("Tailscale")
                nginx = LXC("Nginx")
                ansible = LXC("Ansible")

                tailscale >> Edge(style="invis") >> nginx >> Edge(style="invis") >> ansible

        with Cluster("Physical Host: pve-02 (Laptop)", graph_attr=host_box_attr):
            pve02 = Server("pve-02")

            with Cluster("k8s-app-01 (App Node)", graph_attr=vm_box_attr):
                cilium_app = Pod("Cilium CNI")
                chaos = Pod("Chaos Mesh")
                podinfo = Pod("Podinfo")
                juice = Pod("OWASP Juice Shop")
                falco = Pod("Falco")

                cilium_app >> Edge(style="invis") >> chaos
                cilium_app >> Edge(style="invis") >> juice
                chaos - Edge(color="#64748b") - podinfo
                juice - Edge(color="#64748b") - falco

            with Cluster("LXC Utilities", graph_attr=vm_box_attr):
                pihole = LXC("Pi-hole")

        with Cluster("Physical Host: rpi-01 (Raspberry Pi)", graph_attr=host_box_attr):
            rpi01 = Server("Raspberry Pi")

            with Cluster("Infrastructure Services", graph_attr=vm_box_attr):
                qdevice = Server("Corosync QDevice")
                ntp = Server("Chrony NTP (UTC)")

    # Top-to-bottom layout: Raspberry Pi on top, PVE hosts side-by-side below
    rpi01 >> Edge(style="invis") >> pve01
    rpi01 >> Edge(style="invis") >> pve02
    pve01 - Edge(style="invis") - pve02

    # Vertical hierarchy alignment (forces host icons strictly above all inner sub-boxes)
    pve01 >> Edge(style="invis") >> cilium_cp
    pve01 >> Edge(style="invis") >> argocd
    pve01 >> Edge(style="invis") >> tailscale

    pve02 >> Edge(style="invis") >> cilium_app
    pve02 >> Edge(style="invis") >> pihole

    rpi01 >> Edge(style="invis") >> qdevice
    rpi01 >> Edge(style="invis") >> ntp

    ntp >> Edge(color="#f97316", style="dashed", penwidth="2.2") >> pve01
    ntp >> Edge(color="#f97316", style="dashed", penwidth="2.2") >> pve02

graph_attr_gitops = {
    "fontsize": "28",
    "fontname": "Helvetica Neue, Helvetica, Arial, sans-serif",
    "pad": "0.8",
    "splines": "ortho",
    "nodesep": "1.0",
    "ranksep": "1.2",
    "bgcolor": "#f8fafc",
    "fontcolor": "#0f172a",
}

with Diagram(
    "GitOps Flow",
    show=False,
    direction="LR",
    curvestyle="ortho",
    graph_attr=graph_attr_gitops,
    node_attr=node_attr,
    edge_attr=edge_attr,
    filename="docs/assets/gitops-flow",
    outformat="png",
):
    with Cluster("Source Control", graph_attr=host_box_attr):
        git = Git("Git Repository")

    with Cluster("Continuous Delivery", graph_attr=host_box_attr):
        argocd = Argocd("ArgoCD")

    with Cluster("Applications", graph_attr=host_box_attr):
        podinfo = Pod("Podinfo")
        juice = Pod("OWASP Juice Shop")

    with Cluster("Security & Chaos", graph_attr=host_box_attr):
        chaos = Pod("Chaos Mesh")
        falco = Pod("Falco")

    with Cluster("Observability", graph_attr=host_box_attr):
        prom = Prometheus("Prometheus")
        otel = Pod("OTel Collector")

    with Cluster("Dashboards", graph_attr=host_box_attr):
        grafana = Grafana("Grafana")

    # GitOps deployment flow
    git >> Edge(color="#d97706", penwidth="2.0") >> argocd
    argocd >> Edge(color="#3182ce", penwidth="1.8") >> podinfo
    argocd >> Edge(color="#3182ce", penwidth="1.8") >> juice
    argocd >> Edge(color="#3182ce", penwidth="1.8") >> prom
    argocd >> Edge(color="#3182ce", penwidth="1.8") >> grafana
    argocd >> Edge(color="#3182ce", penwidth="1.8") >> chaos
    argocd >> Edge(color="#3182ce", penwidth="1.8") >> falco

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
