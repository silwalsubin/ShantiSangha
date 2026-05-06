# Wise Cat — Python FastAPI service.
# Internal-only: reachable from the .NET ECS task via an internal ALB.
# Hits Finnhub for market data; .NET caches everything in RDS.

# ECR

resource "aws_ecr_repository" "wisecat" {
  name                 = "${var.app_name}-wisecat"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ecr_lifecycle_policy" "wisecat" {
  repository = aws_ecr_repository.wisecat.name

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

# Logs

resource "aws_cloudwatch_log_group" "wisecat" {
  name              = "/ecs/${var.app_name}-wisecat"
  retention_in_days = 30
}

# Security groups

resource "aws_security_group" "wisecat_alb" {
  name        = "${var.app_name}-wisecat-alb-sg"
  description = "Internal ALB for wisecat - only the .NET API task reaches it"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
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

resource "aws_security_group" "wisecat" {
  name        = "${var.app_name}-wisecat-sg"
  description = "wisecat ECS task - ingress from internal ALB only"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.wisecat_alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Internal ALB

resource "aws_lb" "wisecat" {
  name               = "${var.app_name}-wisecat-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.wisecat_alb.id]
  subnets            = aws_subnet.public[*].id
}

resource "aws_lb_target_group" "wisecat" {
  name        = "${var.app_name}-wisecat-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/healthz"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }
}

resource "aws_lb_listener" "wisecat" {
  load_balancer_arn = aws_lb.wisecat.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wisecat.arn
  }
}

# Task definition

resource "aws_ecs_task_definition" "wisecat" {
  family                   = "${var.app_name}-wisecat"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([{
    name      = "${var.app_name}-wisecat"
    image     = "${aws_ecr_repository.wisecat.repository_url}:latest"
    essential = true

    portMappings = [{
      containerPort = 8000
      protocol      = "tcp"
    }]

    environment = [
      { name = "AWS_REGION", value = var.aws_region },
      { name = "LOG_LEVEL", value = "INFO" }
    ]

    secrets = [
      {
        name      = "WISECAT_INTERNAL_KEY"
        valueFrom = aws_secretsmanager_secret.wisecat_internal_key.arn
      },
      {
        name      = "WISECAT_FINNHUB_API_KEY"
        valueFrom = aws_secretsmanager_secret.finnhub_api_key.arn
      }
    ]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.wisecat.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "curl -fsS http://localhost:8000/healthz || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 30
    }
  }])
}

# Service

resource "aws_ecs_service" "wisecat" {
  name            = "${var.app_name}-wisecat"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.wisecat.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.wisecat.id]
    assign_public_ip = true # needed to reach Finnhub; private subnets have no NAT
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.wisecat.arn
    container_name   = "${var.app_name}-wisecat"
    container_port   = 8000
  }

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  depends_on = [aws_lb_listener.wisecat]

  lifecycle {
    ignore_changes = [task_definition]
  }
}

output "wisecat_internal_url" {
  description = "Internal URL the .NET API uses to reach wisecat. Resolves to a private IP via the internal ALB."
  value       = "http://${aws_lb.wisecat.dns_name}"
}
