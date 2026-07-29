terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.dns]
    }
  }
}

# Inputs into this module

variable "environment" {
  type        = string
  description = "The name of the environment in which this module is being invoked"
  validation {
    condition     = contains(["sand", "dev", "uat", "perf", "stage", "prod", "core", "shared"], var.environment)
    error_message = "Environment must be one of sand, dev, uat, perf, stage, prod, core or shared."
  }
}

variable "name_prefix" {
  type        = string
  description = "Used for naming all resources created"
  validation {
    condition = (
      can(regex("^[a-z0-9_]+$", var.name_prefix)) && (length(var.name_prefix) <= 12)
    )
    error_message = "Name prefix must be numbers, lowercase letters and underscores and no more than 12 characters long."
  }
}

# Tags to add on to the default set on the provider
variable "tags" {
  type        = map(string)
  description = "Additional tags to be applied to all resources created by this module"
  default     = {}
}

variable "dns_names" {
  type        = list(string)
  description = "DNS names to add"
  validation {
    condition     = length(var.dns_names) > 0
    error_message = "DNS names need to be added"
  }
}

variable "price_class" {
  type        = string
  description = "The price class to use."
  default     = "100"
  validation {
    condition     = contains(["100", "200", "All"], var.price_class)
    error_message = "The price class needs to be one of 100, 200 or All https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/PriceClass.html."
  }
}

variable "s3_bucket_primary" {
  type        = string
  description = "The primary S3 bucket to use for the distribution origin"
  default     = null
}

variable "s3_bucket_secondary" {
  type        = string
  description = "An optional secondary S3 bucket to use for the distribution origin"
  default     = null
  validation {
    condition     = var.s3_bucket_primary != null || var.s3_bucket_secondary == null
    error_message = "The secondary bucket cannot be defined without first setting the primary bucket."
  }
}

variable "logging_bucket" {
  type        = string
  description = "The name of the S3 bucket to use for storage of access logs"
}

variable "hosted_zone_id" {
  type        = string
  description = "The hosted zone ID in which the dns_name will be, if created"
  default     = null
  validation {
    condition = (
      # Can be 13-32 chars including starting with a Z, upper case characters with numbers allowed
      # https://docs.aws.amazon.com/Route53/latest/APIReference/API_HostedZone.html
      can(regex("^Z[A-Z0-9]{12,31}$", var.hosted_zone_id))
    )
    error_message = "hosted_zone_id passed does not look like a Hosted Zone ID"
  }
}

variable "default_root_object" {
  type        = string
  description = "The object CloudFront returns when an end user requests the root URL"
  default     = "index.html"
}

variable "domain_name_origin" {
  type        = string
  description = "Enables the use of any specified domain name as the origin"
  default     = null
  validation {
    condition     = !(var.s3_bucket_primary != null && var.domain_name_origin != null)
    error_message = "Both s3_bucket_primary and domain_name_origin cannot be set at the same time i.e. only one origin type is allowed"
  }
}

variable "origin_protocol_policy" {
  type        = string
  description = "Protocol(s) to use for origin access"
  default     = "https-only"
  validation {
    condition     = contains(["https-only", "http-only"], var.origin_protocol_policy)
    error_message = "Origin access must be either https-only (preferred) or http-only."
  }
}

variable "origin_request_policy" {
  type        = string
  description = "Request policy to use for origin access"
  default     = "Managed-AllViewerExceptHostHeader"
}

variable "origin_cache_policy" {
  type        = string
  description = "Caching policy to use for origin"
  default     = "Managed-CachingOptimized"
}

variable "allowed_cidrs" {
  type        = list(string)
  description = "A list of CIDRs which may access this distribution"
  default     = []
}

variable "enable_waf" {
  type        = bool
  description = "enable web application firewall for the cluster"
  default     = false
}

variable "trusted_cidrs" {
  type        = map(list(string))
  description = "Map of location name to list of trusted IPv4 CIDRs which are permanently exempt from WAF rules (e.g. office and VPN egress IPs)."
  default     = {}
}

variable "waf_exempt_cidrs" {
  type        = list(string)
  description = "IP addresses to temporarily exempt from WAF, for the purposes of pen tests and similar."
  default     = []
  validation {
    condition = alltrue([for cidr in var.waf_exempt_cidrs : can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}\\/([0-9]|[1-2][0-9]|3[0-2])$", cidr))
    ])
    error_message = "WAF exemptions must be in CIDR format."
  }
}

variable "waf_allow_rule_group_arns" {
  type        = list(string)
  description = "additional custom allow rule groups"
  default     = []
}

variable "waf_managed_block_rule_group_names" {
  type        = list(string)
  description = "Additional AWS managed block rule groups"
  default     = []
}

variable "waf_block_rule_group_arns" {
  type        = list(string)
  description = "additional custom block rule groups"
  default     = []
}

variable "standard_managed_waf_rule_exclusions" {
  type    = map(list(string))
  default = {}
  validation {
    condition = alltrue([
      for key in keys(var.standard_managed_waf_rule_exclusions) :
      contains(
        [
          "AWSManagedRulesCommonRuleSet",
          "AWSManagedRulesKnownBadInputsRuleSet",
          "AWSManagedRulesSQLiRuleSet",
          "AWSManagedRulesLinuxRuleSet",
          "AWSManagedRulesUnixRuleSet",
          "AWSManagedRulesAmazonIpReputationList"
        ],
        key
      )
    ])

    error_message = "Keys in the map must be one of the following: AWSManagedRulesCommonRuleSet, AWSManagedRulesKnownBadInputsRuleSet, AWSManagedRulesSQLiRuleSet, AWSManagedRulesLinuxRuleSet, AWSManagedRulesUnixRuleSet, AWSManagedRulesAmazonIpReputationList."
  }
}

variable "account_shortname" {
  type        = string
  description = "Optional short name for the current account, used in resource name suffixes. Falls back to the raw account ID when not set."
  default     = null
}
