module "cloudfront" {
  source                        = "terraform-aws-modules/cloudfront/aws"
  version                       = "5.0.0"
  web_acl_id                    = var.enable_waf ? aws_wafv2_web_acl.waf_acl[0].arn : null
  aliases                       = var.dns_names
  comment                       = "Cloudfront distribution for ${var.name_prefix}"
  is_ipv6_enabled               = true
  price_class                   = "PriceClass_${var.price_class}"
  wait_for_deployment           = false
  create_origin_access_identity = true
  origin_access_identities      = local.origin_access_identities
  origin                        = local.origins
  origin_group                  = local.origin_group

  default_cache_behavior = {
    target_origin_id       = var.s3_bucket_primary != null ? "s3_primary" : "dns_primary"
    viewer_protocol_policy = "allow-all"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]
    compress        = true
    query_string    = true
  }

  default_root_object = var.default_root_object

  ordered_cache_behavior = [
    {
      path_pattern           = "/*"
      target_origin_id       = var.s3_bucket_primary != null ? "s3_primary" : "dns_primary"
      viewer_protocol_policy = "redirect-to-https"

      allowed_methods          = var.s3_bucket_primary != null ? ["GET", "HEAD", "OPTIONS"] : ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
      cached_methods           = ["GET", "HEAD"]
      compress                 = true
      query_string             = true
      cache_policy_id          = var.domain_name_origin != null ? data.aws_cloudfront_cache_policy.cache_policy_id[0].id : ""
      origin_request_policy_id = var.domain_name_origin != null ? data.aws_cloudfront_origin_request_policy.origin_request_policy_id[0].id : ""
      use_forwarded_values     = var.domain_name_origin != null ? false : true

      lambda_function_association = length(var.allowed_cidrs) > 0 ? {
        viewer-request = {
          lambda_arn = "${module.ip_restrict[0].lambda_function_qualified_arn}"
        }
      } : {}
    }
  ]

  # Cloudfront SSL configuration
  viewer_certificate = {
    acm_certificate_arn      = module.cloudfront_cert[0].certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  # Cloudfront logging configuration
  logging_config = {
    bucket = data.aws_s3_bucket.logging.bucket_domain_name
    prefix = "${var.environment}/cloudfront/${var.name_prefix}"
  }
  tags = local.tags
}

data "aws_cloudfront_cache_policy" "cache_policy_id" {
  count = (var.domain_name_origin != null) ? 1 : 0
  name  = var.origin_cache_policy
}

data "aws_cloudfront_origin_request_policy" "origin_request_policy_id" {
  count = (var.domain_name_origin != null) ? 1 : 0
  name  = var.origin_request_policy
}

locals {
  origins = merge(
    var.s3_bucket_primary != null ? {
      s3_primary = {
        domain_name = data.aws_s3_bucket.primary[0].bucket_regional_domain_name
        s3_origin_config = {
          origin_access_identity = "s3_primary"
        }
      }
    } : {},

    var.s3_bucket_secondary != null ? {
      s3_primary = {
        domain_name = data.aws_s3_bucket.secondary[0].bucket_regional_domain_name
        s3_origin_config = {
          origin_access_identity = "s3_secondary"
        }
      }
    } : {},

    var.domain_name_origin != null ? {
      dns_primary = {
        domain_name = var.domain_name_origin
        custom_origin_config = {
          http_port              = 80
          https_port             = 443
          origin_protocol_policy = var.origin_protocol_policy
          origin_ssl_protocols   = toset(["TLSv1.2"])
        }
      }
    } : {}
  )

  origin_access_identities = merge(
    var.s3_bucket_secondary != null ?
    {
      s3_secondary = "Origin access identity for ${var.s3_bucket_secondary}"
    } : {},
    var.s3_bucket_primary != null ? {
      s3_primary = "Origin access identity for ${var.s3_bucket_primary}"
    } : {}
  )

  origin_group = (var.s3_bucket_secondary != null) ? {
    group_one = {
      failover_status_codes      = [500, 502, 503, 504]
      primary_member_origin_id   = "s3_primary"
      secondary_member_origin_id = "s3_secondary"
      # TODO: Change origin timeouts from the default? https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/high_availability_origin_failover.html#controlling-attempts-and-timeouts
      # "Origin connection timeout ... By default, CloudFront waits 10 seconds to establish a connection" - could be less
      # "Origin connection attempts ... By default, CloudFront tries 3 times to connect" - probably fine
      # "Origin response timeout ... By default, CloudFront waits for 30 seconds" - should definitely be less
    }
  } : {}
}

# Cloudfront Origin S3 buckets
data "aws_s3_bucket" "primary" {
  count  = (var.s3_bucket_primary != null) ? 1 : 0
  bucket = var.s3_bucket_primary
}

data "aws_s3_bucket" "secondary" {
  count  = (var.s3_bucket_secondary != null) ? 1 : 0
  region = module.helpers.failover_region_name
  bucket = var.s3_bucket_secondary
}

# Logging bucket is usually provided by the environment
data "aws_s3_bucket" "logging" {
  bucket = var.logging_bucket
}

resource "terraform_data" "validation" {
  lifecycle {
    precondition {
      condition     = !(var.s3_bucket_primary != null && var.domain_name_origin != null)
      error_message = "Both s3_bucket_primary and domain_name_origin cannot be set at the same time."
    }

    precondition {
      condition     = var.s3_bucket_primary != null || var.domain_name_origin != null
      error_message = "At least one of s3_bucket_primary or domain_name_origin must be set."
    }
  }
}
