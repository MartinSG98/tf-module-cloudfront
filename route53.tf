data "aws_route53_zone" "env_zone" {
  count   = (var.hosted_zone_id != null) ? 1 : 0
  zone_id = var.hosted_zone_id

  provider = aws.dns
}

resource "aws_route53_record" "dns_record" {
  for_each = toset([for name in var.dns_names : name if endswith(name, data.aws_route53_zone.env_zone[0].name)])
  zone_id  = data.aws_route53_zone.env_zone[0].id
  name     = each.value
  type     = "A"

  alias {
    name                   = module.cloudfront.cloudfront_distribution_domain_name
    zone_id                = module.cloudfront.cloudfront_distribution_hosted_zone_id
    evaluate_target_health = false
  }
  provider = aws.dns
}
