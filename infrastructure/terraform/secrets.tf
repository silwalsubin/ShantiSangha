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

# Optional: Firebase service account (for FCM push notifications)

locals {
  firebase_enabled = nonsensitive(var.firebase_service_account_json != "")
}

resource "aws_secretsmanager_secret" "firebase" {
  count = local.firebase_enabled ? 1 : 0
  name  = "${var.app_name}/firebase_service_account_json"
}

resource "aws_secretsmanager_secret_version" "firebase" {
  count         = local.firebase_enabled ? 1 : 0
  secret_id     = aws_secretsmanager_secret.firebase[0].id
  secret_string = var.firebase_service_account_json
}

# Wise Cat — Finnhub API key (provided via TF var; rotate via tfvars).
# IAM (lambda:InvokeFunction on the ECS task role) is the auth boundary
# between the .NET API and the wisecat Lambda; no shared bearer token needed.
resource "aws_secretsmanager_secret" "finnhub_api_key" {
  name = "${var.app_name}/finnhub_api_key"
}

resource "aws_secretsmanager_secret_version" "finnhub_api_key" {
  secret_id     = aws_secretsmanager_secret.finnhub_api_key.id
  secret_string = var.finnhub_api_key
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
