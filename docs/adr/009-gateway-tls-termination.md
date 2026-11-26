# ADR 009: Gateway TLS Termination

- **Status:** Proposed
- **Date:** 2026-11-26
- **Author:** Victoria Cheng

## Context and Problem Statement

Currently, the external Nginx reverse proxy LXC (ADR 005) serves all `*.homelab.local` dashboards over plain HTTP (port `80`). This creates two issues:

- **Broken `Secure` Cookie Authentication:** Modern web applications such as ArgoCD and Grafana set session cookies with the `Secure` flag. Browsers reject `Secure` cookies over plain HTTP (RFC 6265bis), causing login failures and infinite redirect loops.
- **Unencrypted Browser Traffic:** Browsers flag plain HTTP dashboards as "Not Secure", and configuring individual TLS certificates on every backend service is redundant while leaving HTTP-only backends (such as Hubble UI and Pi-hole) uncovered.

## Decision Outcome

This decision upgrades the external Nginx reverse proxy LXC (`nginx`) to terminate TLS for all `*.homelab.local` virtual hosts:

1. **Wildcard TLS Certificate (`*.homelab.local`):** Provision a self-signed wildcard TLS certificate on the `nginx` container via Ansible (`ansible/playbooks/05-setup-nginx.yml`).
2. **HTTPS Listeners & HTTP Redirects:** Update Nginx virtual host configurations to listen on port `443` with TLS enabled and redirect all plain HTTP (port `80`) traffic to HTTPS.
3. **Internal Upstream Proxying:** Terminate client TLS at Nginx and proxy requests internally to each backend endpoint (for example, ArgoCD on `30443` HTTPS, Hubble UI on `31235` HTTP, and Pi-hole Admin on `80` HTTP).

## Consequences

### Positive

- **Fixes `Secure` Cookie Logins:** Applications such as ArgoCD and Grafana operate over HTTPS, preventing browser cookie rejections and login redirect loops.
- **Centralized TLS Termination:** One wildcard certificate on `nginx` covers all `*.homelab.local` subdomains, including services that only listen on HTTP internally.
- **Encrypted Workstation-to-Gateway Traffic:** Dashboard sessions between client workstations and the reverse proxy are encrypted.

### Negative

- **Self-Signed Trust Warning:** Browsers will display a certificate warning on `https://*.homelab.local` until the self-signed certificate or local Root CA is imported into the client workstation trust store.
- **Certificate Rotation:** Self-signed certificates require periodic renewal via Ansible upon expiration.

## Verification

- [ ] **Nginx Syntax:** Run `nginx -t` on the `nginx` container after deploying updated virtual host configs.
- [ ] **HTTP Redirect:** Verify `http://argocd.homelab.local` redirects to `https://argocd.homelab.local`.
- [ ] **Dashboard Authentication:** Verify ArgoCD and Grafana logins complete over HTTPS without cookie redirect loops.
