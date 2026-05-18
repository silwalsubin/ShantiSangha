# Cloud Map private DNS namespace so the .NET API can resolve the IBKR
# gateway sidecar by name. Splitting the gateway into its own ECS service
# lets the API roll deploys cleanly (50/200) while the gateway stays at
# 0/100 (its EFS-backed session can't safely overlap two task replicas
# during a deploy).

resource "aws_service_discovery_private_dns_namespace" "main" {
  name        = "shantisangha.local"
  description = "Internal service discovery for inter-service calls (e.g. API to IBKR gateway)"
  vpc         = aws_vpc.main.id
}
