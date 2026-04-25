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

# S3 bucket for friend chat media (images, voice messages between friends).
# Kept separate from the voice bucket so its retention, IAM, and lifecycle
# can evolve independently — the voice bucket holds solo recordings consumed
# only by the owning user, while this one holds content shared between two
# users and is hard-deleted when a friendship ends.

resource "aws_s3_bucket" "friends_media" {
  bucket = "${var.app_name}-friends-media-${data.aws_caller_identity.current.account_id}"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "friends_media" {
  bucket = aws_s3_bucket.friends_media.id
  versioning_configuration {
    status = "Disabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "friends_media" {
  bucket = aws_s3_bucket.friends_media.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "friends_media" {
  bucket                  = aws_s3_bucket.friends_media.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CORS — allows the iOS app (or future web client) to PUT directly via
# presigned URL when sending an image or voice message.
resource "aws_s3_bucket_cors_configuration" "friends_media" {
  bucket = aws_s3_bucket.friends_media.id

  cors_rule {
    allowed_headers = ["Content-Type"]
    allowed_methods = ["PUT", "GET"]
    allowed_origins = ["*"]
    max_age_seconds = 3000
  }
}

# Lifecycle — clean up orphaned uploads (object key written but message row
# never committed) after 14 days. Committed messages are deleted explicitly
# when a friendship ends, not by lifecycle.
resource "aws_s3_bucket_lifecycle_configuration" "friends_media" {
  bucket = aws_s3_bucket.friends_media.id

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

# Grant ECS task role access to both buckets — voice (solo recordings) and
# friends_media (shared chat media).
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
      Resource = [
        "${aws_s3_bucket.voice.arn}/*",
        "${aws_s3_bucket.friends_media.arn}/*"
      ]
    }]
  })
}
