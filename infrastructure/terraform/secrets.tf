# All sensitive app config stored in Secrets Manager.
# The ECS task execution role has permission to read these at runtime.

locals {
  all_secrets = {
    clerk_authority      = var.clerk_authority
    clerk_webhook_secret = var.clerk_webhook_secret
    openai_api_key       = var.openai_api_key
    langfuse_secret_key  = var.langfuse_secret_key
  }

  # Filter out empty values — Secrets Manager rejects empty strings
  secrets = { for k, v in local.all_secrets : k => v if v != "" }
}

resource "aws_secretsmanager_secret" "app" {
  for_each = local.secrets
  name     = "${var.app_name}/${each.key}"
}

resource "aws_secretsmanager_secret_version" "app" {
  for_each      = local.secrets
  secret_id     = aws_secretsmanager_secret.app[each.key].id
  secret_string = each.value
}
