# 1. Request the ACM Wildcard Certificate
resource "aws_acm_certificate" "cert" {
  domain_name       = "sctp-sandbox.com"
  validation_method = "DNS"

  # Include the wildcard variant to cover all subdomains
  subject_alternative_names = [
    "*.sctp-sandbox.com"
  ]

  tags = {
    Environment = "staging"
    ManagedBy   = "Terraform"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# 2. Look up your existing Route 53 Hosted Zone ID automatically
data "aws_route53_zone" "selected" {
  name         = "sctp-sandbox.com"
  private_zone = false
}

# 3. Automatically create the DNS CNAME records required by ACM for validation
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.selected.zone_id
}

# 4. Wait for the certificate validation to complete
resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

# 5. Output the ARN for your Ingress annotations
output "acm_certificate_arn" {
  value       = aws_acm_certificate_validation.cert.certificate_arn
  description = "The ARN of the validated ACM wildcard certificate"
}