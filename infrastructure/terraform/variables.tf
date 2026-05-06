variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "production"
}

variable "app_name" {
  description = "Application name used for resource naming"
  type        = string
  default     = "shantisangha"
}

# --- Compute ---

variable "task_cpu" {
  description = "ECS Fargate task vCPU units (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 512
}

variable "task_memory" {
  description = "ECS Fargate task memory in MB"
  type        = number
  default     = 1024
}

variable "desired_count" {
  description = "Number of ECS task replicas"
  type        = number
  default     = 1
}

# --- Database ---

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
  default     = "shantisangha"
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

# --- App secrets (stored in Secrets Manager) ---

variable "clerk_authority" {
  description = "Clerk JWT authority URL (e.g. https://xxx.clerk.accounts.dev)"
  type        = string
  sensitive   = true
}

variable "clerk_webhook_secret" {
  description = "Clerk webhook signing secret"
  type        = string
  sensitive   = true
}

variable "openai_api_key" {
  description = "OpenAI API key"
  type        = string
  sensitive   = true
}

variable "domain_name" {
  description = "Custom domain name for frontend"
  type        = string
  default     = "shantisangha.com"
}

variable "firebase_service_account_json" {
  description = "Firebase Admin SDK service account JSON (for push notifications)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "langfuse_public_key" {
  description = "Langfuse public key (optional, leave empty to disable)"
  type        = string
  default     = ""
}

variable "langfuse_secret_key" {
  description = "Langfuse secret key (optional)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "finnhub_api_key" {
  description = "Finnhub API key — used by the wisecat Python service for market data"
  type        = string
  sensitive   = true
  default     = ""
}
