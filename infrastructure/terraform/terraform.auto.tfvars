# Non-sensitive defaults — committed to git.
# Sensitive values (db_password, api keys, etc.) are passed via
# TF_VAR_* environment variables from GitHub secrets.

aws_region  = "us-east-1"
environment = "production"
app_name    = "shantisangha"

task_cpu      = 512
task_memory   = 1024
desired_count = 1

db_username       = "shantisangha"
db_instance_class = "db.t3.micro"

r2_bucket_name      = "shantisangha-voice"
langfuse_public_key = ""
