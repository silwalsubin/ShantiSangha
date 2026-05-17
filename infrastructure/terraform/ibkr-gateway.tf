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
    # `/sso/Login` returns 200 with the login HTML page regardless of
    # auth state, so it's a stable health signal. The gateway uses a
    # self-signed cert; ALB doesn't validate by default for HTTPS targets.
    path                = "/sso/Login"
    protocol            = "HTTPS"
    matcher             = "200"
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
  description              = "ALB → IBKR gateway sidecar"
}

# ALB SG must accept inbound 443 traffic from the public internet.
resource "aws_security_group_rule" "alb_https_in" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
  description       = "Public HTTPS for gateway subdomain"
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
