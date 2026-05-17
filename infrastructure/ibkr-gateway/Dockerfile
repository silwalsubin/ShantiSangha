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

# Default port the gateway listens on. The .NET API connects to this
# over loopback; the ECS task's awsvpc network namespace keeps it
# unreachable from outside the task.
EXPOSE 5000

# `bin/run.sh root/conf.yaml` is IBKR's published entrypoint. The conf
# file ships in the ZIP and binds to all interfaces inside the container
# — fine for loopback-only access within an ECS task.
CMD ["bin/run.sh", "root/conf.yaml"]
