# IBKR Client Portal Gateway sidecar — Java app that handles the IBKR
# Web API session for Individual accounts (Institutional/Advisor accounts
# can use OAuth 2.0 / private_key_jwt directly; Individual accounts must
# use the gateway).
#
# Lives in the same ECS task as the .NET API, exposed only on localhost.
# Session cookie persists on EFS so deploys/restarts don't force a fresh
# ~daily IBKR 2FA login. User authenticates via a YARP-proxied URL
# (https://api.shantisangha.com/ibkr-gateway/) — the .NET API gates the
# proxy with Clerk auth so only the owner reaches the gateway login.

# ---------- ECR repository for our custom gateway image ---------------------

resource "aws_ecr_repository" "ibkr_gateway" {
  name                 = "${var.app_name}-ibkr-gateway"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ecr_lifecycle_policy" "ibkr_gateway" {
  repository = aws_ecr_repository.ibkr_gateway.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}

# ---------- EFS for session persistence -------------------------------------

resource "aws_efs_file_system" "ibkr_gateway" {
  creation_token = "${var.app_name}-ibkr-gateway"
  encrypted      = true

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = {
    Name = "${var.app_name}-ibkr-gateway"
  }
}

resource "aws_efs_access_point" "ibkr_gateway" {
  file_system_id = aws_efs_file_system.ibkr_gateway.id

  posix_user {
    uid = 1000
    gid = 1000
  }

  root_directory {
    path = "/gateway-state"
    creation_info {
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = "0755"
    }
  }
}

# Allow NFS (port 2049) from the ECS task SG to EFS.

resource "aws_security_group" "ibkr_gateway_efs" {
  name        = "${var.app_name}-ibkr-gateway-efs-sg"
  description = "NFS access for the IBKR gateway session EFS"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Mount targets — one per public subnet so any task replica can reach EFS.

resource "aws_efs_mount_target" "ibkr_gateway" {
  count           = length(aws_subnet.public)
  file_system_id  = aws_efs_file_system.ibkr_gateway.id
  subnet_id       = aws_subnet.public[count.index].id
  security_groups = [aws_security_group.ibkr_gateway_efs.id]
}

# ---------- Subdomain (gateway.shantisangha.com → ALB direct) --------------
#
# Why a subdomain: IBKR's gateway is a SPA that hardcodes absolute paths
# (e.g. `/sso/Login`, `/v1/api/...`) in its minified JS bundles. Hosting it
# behind a path prefix like `/api/ibkr-gateway/*` breaks every URL inside
# those bundles. The cleanest fix is to give the gateway its own root by
# pointing a subdomain straight at the ALB target group on port 5000.

locals {
  gateway_domain_name = "gateway.${var.domain_name}"
}

# Dedicated ACM cert for the subdomain. Lives in us-east-1 alongside the
# ALB (no cross-region complications). Validation is DNS-based via the
# existing Route53 zone.
resource "aws_acm_certificate" "ibkr_gateway" {
  domain_name       = local.gateway_domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "ibkr_gateway_validation" {
  for_each = {
    for dvo in aws_acm_certificate.ibkr_gateway.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = aws_route53_zone.main.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "ibkr_gateway" {
  certificate_arn         = aws_acm_certificate.ibkr_gateway.arn
  validation_record_fqdns = [for r in aws_route53_record.ibkr_gateway_validation : r.fqdn]
}

# Route53 alias so the subdomain resolves to the ALB. Apex shantisangha.com
# already points at CloudFront via dns.tf; this lives alongside.
resource "aws_route53_record" "ibkr_gateway" {
  zone_id = aws_route53_zone.main.zone_id
  name    = local.gateway_domain_name
  type    = "A"

  alias {
    name                   = aws_lb.api.dns_name
    zone_id                = aws_lb.api.zone_id
    evaluate_target_health = true
  }
}

# Target group for the gateway sidecar (port 5000 on the ECS task).
# The ECS service registers the same task in both the api (8080) and
# ibkr_gateway (5000) target groups — see app.tf load_balancer blocks.
resource "aws_lb_target_group" "ibkr_gateway" {
  name        = "${var.app_name}-gateway-tg"
  port        = 5000
  protocol    = "HTTPS"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    # The gateway's default conf.yaml only allows traffic from 127.*
    # (localhost). ALB health checks come from the VPC subnet 10.0.x.x
    # and get 403'd at the gateway's IP allowlist before the URL is
    # evaluated. We accept any 2xx/4xx as "alive" — a 403 here proves
    # the gateway is up and listening; real auth happens via the proxied
    # browser session via the public subdomain (no IP restriction once
    # the request reaches the gateway from the loopback ALB target).
    #
    # Long-term fix: patch the gateway's conf.yaml to include 10.0.0.0/16
    # in ips.allow, then tighten this matcher back to 200.
    # `/` serves the gateway's SPA index.html and reliably returns 200
    # once the JVM is bound to port 5000 — no IBKR session required.
    # We tried `/sso/Login` (404 on this build) and
    # `/v1/api/iserver/auth/status` (intermittent 5xx during transient
    # JVM states, and ALB matchers max out at 499 so 200-599 is rejected).
    path                = "/"
    protocol            = "HTTPS"
    matcher             = "200-499"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 10
  }
}

# HTTPS listener on the ALB serving the gateway subdomain. Lives next to
# the existing port 80 listener (which CloudFront uses for the API).
resource "aws_lb_listener" "ibkr_gateway_https" {
  load_balancer_arn = aws_lb.api.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.ibkr_gateway.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ibkr_gateway.arn
  }
}

# Allow the ALB to reach the gateway sidecar on port 5000.
resource "aws_security_group_rule" "ecs_gateway_from_alb" {
  type                     = "ingress"
  from_port                = 5000
  to_port                  = 5000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.ecs.id
  description              = "ALB to IBKR gateway sidecar"
}

# Allow the API task to reach the gateway task on port 5000 (both share
# the ecs SG). Without this rule the API would resolve the Cloud Map DNS
# but the TCP connection to the gateway's ENI would be refused.
resource "aws_security_group_rule" "ecs_gateway_from_ecs" {
  type                     = "ingress"
  from_port                = 5000
  to_port                  = 5000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ecs.id
  security_group_id        = aws_security_group.ecs.id
  description              = "API ECS task to IBKR gateway task on 5000"
}

# Note: ALB SG already allows public 443 ingress (declared in network.tf
# for the CloudFront origin path). No additional rule needed here.

# ---------- Service discovery: ibkr-gateway.shantisangha.local --------------

resource "aws_service_discovery_service" "ibkr_gateway" {
  name = "ibkr-gateway"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.main.id
    dns_records {
      ttl  = 10
      type = "A"
    }
    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

# ---------- Dedicated ECS task def + service for the gateway ---------------
#
# Hosting the gateway in its own service (instead of as a sidecar in the
# API task) lets the API service roll deploys with 50/200 (near-zero
# downtime) while the gateway stays at 0/100 — necessary because its
# EFS-backed session cookie can't tolerate two replicas writing the
# same file during an overlap deploy window.
#
# API → gateway communication goes through Cloud Map DNS:
# https://ibkr-gateway.shantisangha.local:5000

resource "aws_cloudwatch_log_group" "ibkr_gateway" {
  name              = "/ecs/${var.app_name}-ibkr-gateway"
  retention_in_days = 30
}

resource "aws_ecs_task_definition" "ibkr_gateway" {
  family                   = "${var.app_name}-ibkr-gateway"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512
  memory                   = 1024
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  volume {
    name = "ibkr-gateway-state"
    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.ibkr_gateway.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.ibkr_gateway.id
        iam             = "ENABLED"
      }
    }
  }

  container_definitions = jsonencode([{
    name      = "ibkr-gateway"
    image     = "${aws_ecr_repository.ibkr_gateway.repository_url}:latest"
    essential = true

    portMappings = [{
      containerPort = 5000
      protocol      = "tcp"
    }]

    mountPoints = [{
      sourceVolume  = "ibkr-gateway-state"
      containerPath = "/gateway-state"
      readOnly      = false
    }]

    environment = [
      { name = "IBKR_GATEWAY_STATE_DIR", value = "/gateway-state" }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ibkr_gateway.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ibkr-gateway"
      }
    }

    healthCheck = {
      # Accept any HTTP response code as "alive" — the gateway returns 401
      # for /v1/api/iserver/auth/status when no IBKR session is established
      # (the common pre-login state) and `curl -f` would treat that as
      # failure. Without `-f`, curl exits 0 on any response and we keep
      # the container alive. ECS-level health is separate from IBKR-level
      # auth state.
      command     = ["CMD-SHELL", "curl -ks --max-time 5 https://localhost:5000/v1/api/iserver/auth/status -o /dev/null || exit 1"]
      interval    = 30
      timeout     = 10
      retries     = 3
      startPeriod = 90
    }
  }])
}

resource "aws_ecs_service" "ibkr_gateway" {
  name            = "${var.app_name}-ibkr-gateway"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.ibkr_gateway.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  # The IBKR gateway is a JVM that needs ~60s to fully bind port 5000.
  # Without a grace period the ALB health-checks immediately, sees
  # connection-refused or non-200 response, and kills the task before
  # it ever boots. Two minutes covers the JVM cold start with margin.
  health_check_grace_period_seconds = 120

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  # Public-facing target group serving gateway.shantisangha.com for the
  # browser login. Same TG as before, just now exclusively owned by this
  # service (used to be a second registration on the API service).
  load_balancer {
    target_group_arn = aws_lb_target_group.ibkr_gateway.arn
    container_name   = "ibkr-gateway"
    container_port   = 5000
  }

  # Cloud Map registration: the .NET API resolves the gateway by name.
  service_registries {
    registry_arn = aws_service_discovery_service.ibkr_gateway.arn
  }

  # The EFS session cookie can't survive two concurrent gateways. Stop the
  # old one before starting the new one — ~30-60s of gateway-only downtime
  # per deploy. The API service stays up independently.
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  lifecycle {
    ignore_changes = [task_definition]
  }
}

# ---------- Outputs ---------------------------------------------------------

output "ibkr_gateway_ecr_url" {
  description = "ECR URL for the IBKR gateway image. The ibkr-gateway-deploy GitHub Action pushes to this repo with tag :latest."
  value       = aws_ecr_repository.ibkr_gateway.repository_url
}

output "ibkr_gateway_efs_id" {
  description = "EFS file system id holding the IBKR gateway session cookie. Detach manually before destroying the gateway to force a re-login."
  value       = aws_efs_file_system.ibkr_gateway.id
}

output "ibkr_gateway_url" {
  description = "Public URL for the IBKR gateway login. Open in a browser to complete IBKR 2FA — the gateway then persists the session on EFS."
  value       = "https://${local.gateway_domain_name}/"
}
