# All sensitive app config stored in Secrets Manager.
# The ECS task execution role has permission to read these at runtime.
#
# Note: for_each cannot use sensitive values as keys. Required secrets use
# a non-sensitive string set for keys, optional secrets use count.

locals {
  required_secret_names = toset(["clerk_authority", "clerk_webhook_secret", "openai_api_key"])

  # nonsensitive() is safe here: it only reveals whether the value is set, not the value itself
  langfuse_enabled = nonsensitive(var.langfuse_secret_key != "")
}

# Required secrets

resource "aws_secretsmanager_secret" "app" {
  for_each = local.required_secret_names
  name     = "${var.app_name}/${each.key}"
}

resource "aws_secretsmanager_secret_version" "app" {
  for_each  = local.required_secret_names
  secret_id = aws_secretsmanager_secret.app[each.key].id
  secret_string = lookup({
    clerk_authority      = var.clerk_authority
    clerk_webhook_secret = var.clerk_webhook_secret
    openai_api_key       = var.openai_api_key
  }, each.key)
}

# Optional: Langfuse

resource "aws_secretsmanager_secret" "langfuse" {
  count = local.langfuse_enabled ? 1 : 0
  name  = "${var.app_name}/langfuse_secret_key"
}

resource "aws_secretsmanager_secret_version" "langfuse" {
  count         = local.langfuse_enabled ? 1 : 0
  secret_id     = aws_secretsmanager_secret.langfuse[0].id
  secret_string = var.langfuse_secret_key
}
