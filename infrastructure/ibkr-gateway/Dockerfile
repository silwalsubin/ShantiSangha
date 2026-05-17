# IBKR Client Portal Gateway image.
#
# Downloads the official IBKR Java gateway ZIP at build time, runs it on
# port 5000 with the default IBKR self-signed certificate. The image
# itself holds NO credentials — sessions live on an EFS volume mounted
# at /gateway-state in production (see infrastructure/terraform/app.tf).
#
# Why we build our own image: IBKR does not publish an official Docker
# image. Community images exist but vary in trust + maintenance. Building
# from the upstream ZIP keeps the supply chain auditable.
#
# To rebuild: push to main with changes under `infrastructure/ibkr-gateway/`
# — the ibkr-gateway-deploy workflow handles the build + push.

FROM eclipse-temurin:17-jre-jammy

# Curl + unzip needed for the install; ca-certificates so the JRE can
# trust outbound IBKR endpoints during requests.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl unzip ca-certificates \
    && rm -rf /var/lib/apt/lists/*

ARG GATEWAY_URL=https://download2.interactivebrokers.com/portal/clientportal.gw.zip
WORKDIR /opt/clientportal.gw

RUN curl -fSL "${GATEWAY_URL}" -o /tmp/gw.zip \
    && unzip /tmp/gw.zip -d /opt/clientportal.gw \
    && rm /tmp/gw.zip \
    && chmod +x /opt/clientportal.gw/bin/run.sh

# IBKR's default conf.yaml only allows traffic from a fixed set of IP
# ranges (192.*, 131.216.*, 127.0.0.1), which rejects ALB health checks
# and proxied user traffic — both come from the VPC subnet (10.0.x.x).
# Inject `- 0.0.0.0/0` into ips.allow so the gateway accepts traffic
# from anywhere reachable; SG rules already restrict ingress at the
# network layer (only the ALB SG can talk to port 5000), so this is
# not a real reduction in security posture.
#
# The conf.yaml uses 6-space indent on `allow:` and 8-space on list
# items (verified by inspecting the upstream zip's content). Hard-fail
# if the marker isn't found so an upstream format change can't silently
# produce an unreachable gateway.
RUN if grep -qE '^[[:space:]]+allow:[[:space:]]*$' /opt/clientportal.gw/root/conf.yaml; then \
        sed -i '/^[[:space:]]\+allow:[[:space:]]*$/a\        - 0.0.0.0/0' /opt/clientportal.gw/root/conf.yaml; \
    else \
        echo "ERROR: ips.allow marker not found in conf.yaml" >&2; \
        cat /opt/clientportal.gw/root/conf.yaml; \
        exit 1; \
    fi \
    && echo "--- patched conf.yaml ips section ---" \
    && grep -A 6 -E '^[[:space:]]+ips:[[:space:]]*$' /opt/clientportal.gw/root/conf.yaml

# Default port the gateway listens on. The .NET API connects to this
# over loopback; the ECS task's awsvpc network namespace keeps it
# unreachable from outside the task.
EXPOSE 5000

# `bin/run.sh root/conf.yaml` is IBKR's published entrypoint. The conf
# file ships in the ZIP and binds to all interfaces inside the container
# — fine for loopback-only access within an ECS task.
CMD ["bin/run.sh", "root/conf.yaml"]
