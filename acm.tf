module "cloudfront_cert" {
  source = "git::https://github.com/MartinSG98/tf-module-acm_cert.git?ref=1.0.0"

  count                     = var.hosted_zone_id != null ? 1 : 0
  domain_name               = var.dns_names[0]
  subject_alternative_names = var.dns_names
  hosted_zone_id            = var.hosted_zone_id
  tags                      = local.tags
  key_algorithm             = "EC_prime256v1" # Not using default EC_secp384r1 as Userpool domain unable to see certificate
  region                    = "us-east-1"
  providers = {
    aws            = aws
    aws.dnsaccount = aws.dns
  }
}
