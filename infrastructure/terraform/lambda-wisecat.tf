# Wise Cat — Python Lambda. The .NET API task invokes it directly via the AWS
# SDK; IAM is the auth boundary (lambda:InvokeFunction on the task role).

# ECR repository for the Lambda container image

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
  name              = "/aws/lambda/${var.app_name}-wisecat"
  retention_in_days = 30
}

# IAM — execution role for the Lambda function

resource "aws_iam_role" "wisecat_lambda" {
  name = "${var.app_name}-wisecat-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "wisecat_lambda_basic" {
  role       = aws_iam_role.wisecat_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "wisecat_lambda_secrets" {
  name = "${var.app_name}-wisecat-lambda-secrets"
  role = aws_iam_role.wisecat_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = aws_secretsmanager_secret.finnhub_api_key.arn
    }]
  })
}

# Lambda function (container image). On the very first apply, the ECR repo is
# empty so we'd fail to create the function. The python-deploy GH Action pushes
# the real image and `aws lambda update-function-code` flips the URI; the
# lifecycle.ignore_changes block below stops Terraform from clobbering that.
#
# Bootstrap: before the very first `terraform apply`, push any image to the
# repo so it's not empty. Easiest: run python-deploy once after terraform
# creates the ECR repo (it will fail at the lambda update step the first time
# but the ECR push will succeed), THEN run terraform apply again.

resource "aws_lambda_function" "wisecat" {
  function_name = "${var.app_name}-wisecat"
  role          = aws_iam_role.wisecat_lambda.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.wisecat.repository_url}:latest"
  architectures = ["x86_64"]

  memory_size = 1024  # pandas comfortable; tune down later if cold-start dominates
  timeout     = 60

  environment {
    variables = {
      WISECAT_FINNHUB_SECRET_ID = aws_secretsmanager_secret.finnhub_api_key.name
      LOG_LEVEL                 = "INFO"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.wisecat,
    aws_iam_role_policy_attachment.wisecat_lambda_basic,
  ]

  # The image_uri is rolled forward by `aws lambda update-function-code` in CI.
  # Don't fight that on subsequent terraform applies.
  lifecycle {
    ignore_changes = [image_uri]
  }
}

# Allow the .NET API ECS task role to invoke this Lambda.

resource "aws_iam_role_policy" "ecs_invoke_wisecat" {
  name = "${var.app_name}-ecs-invoke-wisecat"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = aws_lambda_function.wisecat.arn
    }]
  })
}

output "wisecat_function_name" {
  description = "Name of the wisecat Lambda function — passed to the .NET API as WISECAT_FUNCTION_NAME."
  value       = aws_lambda_function.wisecat.function_name
}
