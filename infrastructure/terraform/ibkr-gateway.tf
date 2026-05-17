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

# ---------- Outputs ---------------------------------------------------------

output "ibkr_gateway_ecr_url" {
  description = "ECR URL for the IBKR gateway image. The ibkr-gateway-deploy GitHub Action pushes to this repo with tag :latest."
  value       = aws_ecr_repository.ibkr_gateway.repository_url
}

output "ibkr_gateway_efs_id" {
  description = "EFS file system id holding the IBKR gateway session cookie. Detach manually before destroying the gateway to force a re-login."
  value       = aws_efs_file_system.ibkr_gateway.id
}
