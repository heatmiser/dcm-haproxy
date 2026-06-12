# dcm-haproxy

L4 load balancer for OpenShift API and Ingress VIPs in DCM bootstrap deployments.
Provides the TCP/HTTP load balancing that OCP requires for its API endpoint (6443),
Machine Config Server (22623), and application Ingress (80/443) when no external
load balancer is available at the deployment site.

## Container Image

```
quay.io/s4v0/dcm-haproxy:latest
```

Built from `registry.access.redhat.com/ubi9/ubi:9.8` with HAProxy installed via RHSM.
Runs in master-worker mode (`-W`) with host networking, supporting hot config reload
without connection drops.

## OCP Load Balancer Requirements

| Port | Frontend | Backend | Notes |
|------|----------|---------|-------|
| 6443 | `ocp_api` | control plane nodes :6443 | TLS passthrough |
| 22623 | `ocp_machine_config` | control plane nodes :22623 | TLS passthrough |
| 80 | `ocp_ingress_http` | ingress/worker nodes :80 | HTTP mode |
| 443 | `ocp_ingress_https` | ingress/worker nodes :443 | TLS passthrough |
| 8404 | `stats` | — | HAProxy stats UI + `/healthz` |

## Deployment

### Prerequisites

- `elise.quadlet` collection (installed via `requirements.yml`)
- Rootful Podman with systemd Quadlet support
- firewalld
- Cluster topology defined (control plane and ingress node IPs)

### Quick Start

```bash
ansible-playbook playbooks/site.yml -i inventory/hosts.yml \
  -e 'dcm_haproxy_control_plane_nodes=[{"name":"master0","ip":"192.168.1.10"},{"name":"master1","ip":"192.168.1.11"},{"name":"master2","ip":"192.168.1.12"}]' \
  -e 'dcm_haproxy_ingress_nodes=[{"name":"worker0","ip":"192.168.1.20"},{"name":"worker1","ip":"192.168.1.21"}]'
```

Or override in a vars file alongside `config.yaml`.

### Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `dcm_haproxy_image` | `quay.io/s4v0/dcm-haproxy` | Container image |
| `dcm_haproxy_image_tag` | `latest` | Image tag |
| `dcm_haproxy_config_dir` | `/srv/containers/haproxy/config` | Host directory for rendered haproxy.cfg |
| `dcm_haproxy_conf_d_dir` | `/srv/containers/haproxy/conf.d` | Drop-in config directory for Day 3 extensions |
| `dcm_haproxy_control_plane_nodes` | `[]` | List of `{name, ip}` for control plane nodes |
| `dcm_haproxy_ingress_nodes` | `[]` | List of `{name, ip}` for ingress/worker nodes |
| `dcm_haproxy_extra_config` | `""` | Inline haproxy.cfg additions (appended verbatim) |
| `dcm_haproxy_firewall_zone` | `public` | firewalld zone for port rules |

## Day 3 Extensions

Two mechanisms for extending the configuration after initial deployment:

### Inline additions (`dcm_haproxy_extra_config`)

Pass arbitrary haproxy.cfg blocks via the `dcm_haproxy_extra_config` variable and
re-run the playbook to regenerate and hot-reload:

```yaml
dcm_haproxy_extra_config: |
  frontend custom_app
      mode http
      bind *:9090
      default_backend custom_backend

  backend custom_backend
      mode http
      server app0 192.168.1.30:9090 check
```

### Drop-in configs (`conf.d/`)

Place `.cfg` files in the conf.d directory; HAProxy loads them at startup alongside
the main config. HAProxy 2.4+ accepts a directory path as `-f`, so all `*.cfg` files
are loaded automatically.

```bash
cat > /srv/containers/haproxy/conf.d/registry.cfg << 'EOF'
frontend registry
    bind *:5000
    default_backend registry_backend

backend registry_backend
    server quay0 192.168.1.50:5000 check
EOF
```

### Hot Reload (no connection drops)

HAProxy master-worker mode (`-W`) supports live config reload via `SIGUSR2`:

```bash
# Via systemd (preferred)
systemctl kill --signal=SIGUSR2 dcm-haproxy.service

# Via podman directly
podman kill --signal=SIGUSR2 dcm-haproxy
```

HAProxy validates the new config before applying it. If the new config is invalid,
the running workers continue unchanged.

## Monitoring

Stats UI: `http://<bootstrap-node>:8404/haproxy?stats`

Health endpoint (for load balancer health checks): `http://<bootstrap-node>:8404/healthz`

## Repository Structure

```
dcm-haproxy/
├── Containerfile
├── images.txt
├── requirements.yml
├── .github/workflows/
│   ├── ansible-lint.yml
│   └── build.yml
├── playbooks/
│   ├── site.yml
│   └── templates/
│       └── haproxy.cfg.j2
├── tasks/
│   └── render_conf.yml
└── vars/
    └── haproxy.yml
```

## License

Apache-2.0
