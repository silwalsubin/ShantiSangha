output "alb_dns_name" {
  description = "ALB DNS name — point your domain's CNAME here"
  value       = aws_lb.api.dns_name
}

output "ecr_repository_url" {
  description = "ECR repository URL — used in GitHub Actions to push images"
  value       = aws_ecr_repository.api.repository_url
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = aws_db_instance.postgres.address
  sensitive   = true
}

output "redis_endpoint" {
  description = "ElastiCache Redis endpoint"
  value       = "${aws_elasticache_cluster.redis.cache_nodes[0].address}:${aws_elasticache_cluster.redis.cache_nodes[0].port}"
  sensitive   = true
}

output "ecs_cluster_name" {
  description = "ECS cluster name — used in GitHub Actions deploy step"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "ECS service name — used in GitHub Actions deploy step"
  value       = aws_ecs_service.api.name
}

output "voice_bucket_name" {
  description = "S3 bucket for voice file uploads"
  value       = aws_s3_bucket.voice.bucket
}

output "cloudfront_domain" {
  description = "CloudFront domain — point shantisangha.com CNAME here"
  value       = aws_cloudfront_distribution.frontend.domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID — used in GitHub Actions cache invalidation"
  value       = aws_cloudfront_distribution.frontend.id
}

output "frontend_bucket_name" {
  description = "S3 bucket for frontend files — used in GitHub Actions deploy"
  value       = aws_s3_bucket.frontend.bucket
}

output "acm_certificate_validation" {
  description = "DNS records to add in Cloudflare for ACM certificate validation"
  value = {
    for dvo in aws_acm_certificate.frontend.domain_validation_options : dvo.domain_name => {
      type  = dvo.resource_record_type
      name  = dvo.resource_record_name
      value = dvo.resource_record_value
    }
  }
}
