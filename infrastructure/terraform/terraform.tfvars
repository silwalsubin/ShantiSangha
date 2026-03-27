# Copy this to terraform.tfvars and fill in your values.
# NEVER commit terraform.tfvars to git.

aws_region  = "us-east-1"
environment = "production"
app_name    = "shantisangha"

# Compute (these are the cheapest Fargate settings)
task_cpu    = 512
task_memory = 1024
desired_count = 1

# Database
db_username       = "shantisangha"
db_password       = "CHANGE_ME_strong_password_here"
db_instance_class = "db.t3.micro"

# App secrets
clerk_authority      = "https://grown-impala-35.clerk.accounts.dev"
clerk_webhook_secret = "whsec_YOUR_CLERK_WEBHOOK_SECRET"
openai_api_key       = "sk-proj-YOUR_OPENAI_KEY"

# Cloudflare R2 (voice storage)
r2_account_id        = "YOUR_R2_ACCOUNT_ID"
r2_access_key_id     = "YOUR_R2_ACCESS_KEY_ID"
r2_secret_access_key = "YOUR_R2_SECRET_ACCESS_KEY"
r2_bucket_name       = "shantisangha-voice"

# Langfuse (optional — leave empty to disable)
langfuse_public_key = ""
langfuse_secret_key = ""
