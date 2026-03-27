terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend config is passed via -backend-config flags in CI (see .github/workflows/terraform.yml)
  backend "s3" {}
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "shantisangha"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
