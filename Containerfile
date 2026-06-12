FROM registry.access.redhat.com/ubi9/ubi:9.8

# Register, install, unregister in a single layer so credentials never persist
# in the image. Secrets are injected at build time via podman --secret and are
# not visible in image history or layers.
# UBI9 ships /etc/rhsm-host -> /run/secrets/rhsm and
# /etc/pki/entitlement-host -> /run/secrets/etc-pki-entitlement — these tell
# subscription-manager it is inside a container and should defer to host
# subscriptions. Remove them and set SMDEV_CONTAINER_OFF=1 so registration
# proceeds as on a bare-metal host. They are not restored; the runtime load
# balancer service has no RHSM dependency.
RUN --mount=type=secret,id=rhsm_username \
    --mount=type=secret,id=rhsm_password \
    rm -f /etc/rhsm-host /etc/pki/entitlement-host && \
    SMDEV_CONTAINER_OFF=1 subscription-manager register \
      --username="$(cat /run/secrets/rhsm_username)" \
      --password="$(cat /run/secrets/rhsm_password)" \
      --auto-attach && \
    dnf -y install haproxy curl && \
    dnf clean all && \
    rm -rf /var/cache/dnf && \
    mkdir -p /etc/haproxy/conf.d && \
    subscription-manager unregister && \
    subscription-manager clean && \
    rm -rf /var/lib/rhsm /var/log/rhsm

LABEL org.opencontainers.image.source="https://github.com/heatmiser/dcm-haproxy" \
      org.opencontainers.image.description="HAProxy load balancer container image for DCM bootstrap deployments" \
      org.opencontainers.image.licenses="Apache-2.0"

EXPOSE 80/tcp
EXPOSE 443/tcp
EXPOSE 6443/tcp
EXPOSE 22623/tcp
EXPOSE 8404/tcp

CMD ["/usr/sbin/haproxy", "-W", "-db", "-f", "/etc/haproxy/haproxy.cfg", "-f", "/etc/haproxy/conf.d/"]
