data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # Redis URL from ElastiCache
  redis_url = "${aws_elasticache_cluster.redis.cache_nodes[0].address}:${aws_elasticache_cluster.redis.cache_nodes[0].port}"
}

# ECR repository

resource "aws_ecr_repository" "api" {
  name                 = "${var.app_name}-api"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

# CloudWatch log group

resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/${var.app_name}-api"
  retention_in_days = 30
}

# IAM — Task Execution Role (ECS agent: pull ECR image, read secrets, write logs)

resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.app_name}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_managed" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  name = "${var.app_name}-ecs-secrets-policy"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = "arn:aws:secretsmanager:${var.aws_region}:${local.account_id}:secret:${var.app_name}/*"
    }]
  })
}

# IAM — Task Role (the app itself — no extra AWS permissions needed for now)

resource "aws_iam_role" "ecs_task" {
  name = "${var.app_name}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# EFS IAM auth — the IBKR gateway sidecar mounts the persistent session
# volume via `iam = ENABLED`, which means the task role must hold
# elasticfilesystem:Client* on the file system.

resource "aws_iam_role_policy" "ecs_task_efs" {
  name = "${var.app_name}-ecs-task-efs"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "elasticfilesystem:ClientMount",
        "elasticfilesystem:ClientWrite",
        "elasticfilesystem:ClientRootAccess",
      ]
      Resource = aws_efs_file_system.ibkr_gateway.arn
    }]
  })
}

# ECS Cluster

resource "aws_ecs_cluster" "main" {
  name = "${var.app_name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.main.name
  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
  }
}

# ECS Task Definition

resource "aws_ecs_task_definition" "api" {
  family                   = "${var.app_name}-api"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  # The IBKR gateway sidecar used to live in this task. It's now its own
  # service (see ibkr-gateway.tf) so the API can roll deploys at 50/200
  # without dragging the gateway's EFS-bound session through every
  # backend push. API → gateway calls go via Cloud Map:
  # https://ibkr-gateway.shantisangha.local:5000

  container_definitions = jsonencode([
    {
      name      = "${var.app_name}-api"
      image     = "${aws_ecr_repository.api.repository_url}:latest"
      essential = true

      portMappings = [{
        containerPort = 8080
        protocol      = "tcp"
      }]

      environment = [
        { name = "REDIS_URL",              value = local.redis_url },
        { name = "VOICE_BUCKET_NAME",      value = aws_s3_bucket.voice.bucket },
        { name = "FRIENDS_MEDIA_BUCKET_NAME", value = aws_s3_bucket.friends_media.bucket },
        { name = "AWS_REGION",             value = var.aws_region },
        { name = "LANGFUSE_BASE_URL",      value = "https://cloud.langfuse.com" },
        { name = "LANGFUSE_PUBLIC_KEY",    value = var.langfuse_public_key },
        { name = "ASPNETCORE_ENVIRONMENT", value = "Production" },
        { name = "EXPOSE_ERRORS",          value = "true" },
        { name = "FIREBASE_PROJECT_ID",   value = "shantisangha-bc0f9" },
        { name = "FRONTEND_ORIGIN",       value = "https://${var.domain_name},https://${aws_cloudfront_distribution.frontend.domain_name},http://localhost:5173" },
        { name = "WISECAT_FUNCTION_NAME", value = aws_lambda_function.wisecat.function_name },
        # Route through the public ALB URL rather than Cloud Map direct
        # because the gateway's HTTP layer rejects requests coming from
        # the VPC subnet directly (returns 403 Access Denied even though
        # the source IP is in `ips.allow`). The ALB path works because
        # of how ALB forwards (probably proxy-style headers / Host
        # rewriting). Extra ALB hop is negligible at our scale.
        { name = "IBKR_GATEWAY_BASE_URL", value = "https://gateway.${var.domain_name}" }
      ]

      secrets = concat([
        {
          name      = "DATABASE_URL"
          valueFrom = aws_secretsmanager_secret.database_url.arn
        },
        {
          name      = "OPENAI_API_KEY"
          valueFrom = aws_secretsmanager_secret.app["openai_api_key"].arn
        }
      ], local.firebase_enabled ? [
        {
          name      = "FIREBASE_SERVICE_ACCOUNT_JSON"
          valueFrom = aws_secretsmanager_secret.firebase[0].arn
        }
      ] : [])

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.api.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }

      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])
}

# Application Load Balancer

resource "aws_lb" "api" {
  name               = "${var.app_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
}

resource "aws_lb_target_group" "api" {
  name        = "${var.app_name}-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.api.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

# ECS Service

resource "aws_ecs_service" "api" {
  name            = "${var.app_name}-api"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "${var.app_name}-api"
    container_port   = 8080
  }

  # Rolling deploys — gateway is its own service now so the API doesn't
  # need to coordinate with EFS-backed session state during a deploy.
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  depends_on = [aws_lb_listener.http]

  lifecycle {
    ignore_changes = [task_definition]
  }
}
