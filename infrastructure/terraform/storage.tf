# S3 bucket for voice file uploads (Whisper transcription source)

resource "aws_s3_bucket" "voice" {
  bucket = "${var.app_name}-voice-${data.aws_caller_identity.current.account_id}"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "voice" {
  bucket = aws_s3_bucket.voice.id
  versioning_configuration {
    status = "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "voice" {
  bucket = aws_s3_bucket.voice.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "voice" {
  bucket                  = aws_s3_bucket.voice.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CORS — allows the browser to PUT directly to S3 via presigned URL
resource "aws_s3_bucket_cors_configuration" "voice" {
  bucket = aws_s3_bucket.voice.id

  cors_rule {
    allowed_headers = ["Content-Type"]
    allowed_methods = ["PUT"]
    allowed_origins = ["*"]
    max_age_seconds = 3000
  }
}

# Grant ECS task role access to the voice bucket
resource "aws_iam_role_policy" "ecs_task_s3" {
  name = "${var.app_name}-ecs-s3-policy"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject"
      ]
      Resource = "${aws_s3_bucket.voice.arn}/*"
    }]
  })
}
