# All sensitive app config stored in Secrets Manager.
# The ECS task execution role has permission to read these at runtime.

locals {
  required_secret_names = toset(["openai_api_key"])

  # nonsensitive() is safe here: it only reveals whether the value is set, not the value itself
  langfuse_enabled = nonsensitive(var.langfuse_secret_key != "")
}

# Auto-generated database password — no manual management needed
resource "random_password" "db" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "database_url" {
  name = "${var.app_name}/database_url"
}

resource "aws_secretsmanager_secret_version" "database_url" {
  secret_id     = aws_secretsmanager_secret.database_url.id
  secret_string = "Host=${aws_db_instance.postgres.address};Port=5432;Database=shantisangha;Username=${var.db_username};Password=${random_password.db.result}"
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
    openai_api_key = var.openai_api_key
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
