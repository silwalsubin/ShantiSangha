# Route 53 hosted zone for the domain

resource "aws_route53_zone" "main" {
  name = var.domain_name
}

# Point the registered domain's nameservers to this hosted zone
resource "aws_route53domains_registered_domain" "main" {
  domain_name = var.domain_name

  dynamic "name_server" {
    for_each = aws_route53_zone.main.name_servers
    content {
      name = name_server.value
    }
  }
}

# A record — root domain → CloudFront
resource "aws_route53_record" "root" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.frontend.domain_name
    zone_id                = aws_cloudfront_distribution.frontend.hosted_zone_id
    evaluate_target_health = false
  }
}

# ACM certificate DNS validation records
resource "aws_route53_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.frontend.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = aws_route53_zone.main.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 300
  records = [each.value.record]
}

# --- Clerk DNS records ---

resource "aws_route53_record" "clerk_frontend_api" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "clerk.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = ["frontend-api.clerk.services"]
}

resource "aws_route53_record" "clerk_accounts" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "accounts.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = ["accounts.clerk.services"]
}

resource "aws_route53_record" "clerk_mail" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "clkmail.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = ["mail.7k5if83oopx7.clerk.services"]
}

resource "aws_route53_record" "clerk_dkim1" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "clk._domainkey.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = ["dkim1.7k5if83oopx7.clerk.services"]
}

resource "aws_route53_record" "clerk_dkim2" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "clk2._domainkey.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = ["dkim2.7k5if83oopx7.clerk.services"]
}
