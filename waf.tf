# trusted IPs to which WAF rules are not applied
resource "aws_wafv2_ip_set" "waf_ips" {
  count              = var.enable_waf ? 1 : 0
  name               = "${var.name_prefix}_cf-wafi-${module.helpers_us.name_suffix_global}"
  description        = "${var.name_prefix} trusted IP WAF IP set"
  scope              = "CLOUDFRONT"
  region             = "us-east-1"
  ip_address_version = "IPV4"
  addresses = concat(
    flatten(values(var.trusted_cidrs)),
    var.waf_exempt_cidrs
  )
}

# WAF Access control list
resource "aws_wafv2_web_acl" "waf_acl" {
  count       = var.enable_waf ? 1 : 0
  name        = "${var.name_prefix}_cf-waf-${module.helpers_us.name_suffix_global}"
  description = "${var.name_prefix} waf acl"
  scope       = "CLOUDFRONT"
  region      = "us-east-1"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = false
    metric_name                = "${var.name_prefix}_cf_waf_acl-cwm-${module.helpers_us.name_suffix_global}"
    sampled_requests_enabled   = false
  }

  # Rule sets
  # 1. Trusted IP sets - public / private VPC CIDRs
  rule {
    name     = "Trusted_IP_set"
    priority = 0

    action {
      allow {}
    }

    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.waf_ips[0].arn
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = false
      metric_name                = "${var.name_prefix}_cf_waf_trusted_ips-cwm-${module.helpers_us.name_suffix_global}"
      sampled_requests_enabled   = false
    }
  }

  # 2. custom block rule groups passed in from input
  dynamic "rule" {
    for_each = var.waf_block_rule_group_arns

    content {
      name     = "${var.name_prefix}_${rule.key}_cstm_group_block-wafr-${module.helpers_us.name_suffix_global}"
      priority = 100 + rule.key

      action {
        block {}
      }

      statement {
        rule_group_reference_statement {
          arn = rule.value
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = contains(["dev"], var.environment)
        metric_name                = "${var.name_prefix}_cf_${rule.key}_waf_cstm_group_block-cwm-${module.helpers_us.name_suffix_global}"
        sampled_requests_enabled   = contains(["dev"], var.environment)
      }
    }
  }

  # 3.  custom allow rule groups passed in from input
  dynamic "rule" {
    for_each = var.waf_allow_rule_group_arns

    content {
      name     = "${var.name_prefix}_${rule.key}_cstm_group_allow-wafr-${module.helpers_us.name_suffix_global}"
      priority = 200 + rule.key

      action {
        allow {}
      }

      statement {
        rule_group_reference_statement {
          arn = rule.value
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = false
        metric_name                = "${var.name_prefix}_cf_${rule.key}_waf_cstm_group_allow-cwm-${module.helpers_us.name_suffix_global}"
        sampled_requests_enabled   = false
      }
    }
  }

  # 4. Standard set of AWS Managed rule groups which we always include
  dynamic "rule" {
    for_each = local.standard_managed_waf_rules

    content {
      name     = "${var.name_prefix}_${rule.key}_mgd_block-wafr-${module.helpers_us.name_suffix_global}"
      priority = rule.value.priority + 300

      #This is confusing, default action for rule groups is to block however require an overide action to be confirmed even if not used {}
      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = rule.key
          vendor_name = "AWS"

          dynamic "rule_action_override" {
            for_each = rule.value.excluded_rules
            content {
              name = rule_action_override.value
              action_to_use {
                allow {}
              }
            }
          }
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = contains(["dev"], var.environment)
        metric_name                = "${var.name_prefix}_cf_${rule.key}_waf_mgd_block-cwm-${module.helpers_us.name_suffix_global}"
        sampled_requests_enabled   = contains(["dev"], var.environment)
      }
    }
  }

  # 5. block managed rule set passed in from input
  dynamic "rule" {
    for_each = var.waf_managed_block_rule_group_names

    content {
      name     = "${var.name_prefix}_${rule.key}_waf_mgd_block-wafr-${module.helpers_us.name_suffix_global}"
      priority = 400 + index(keys(var.waf_managed_block_rule_group_names), rule.key)

      #This is confusing, default action for rule groups is to block however require an overide action to be confirmed even if not used {}
      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = rule.key
          vendor_name = "AWS"

          dynamic "rule_action_override" {
            for_each = rule.value
            content {
              name = rule_action_override.value
              action_to_use {
                allow {}
              }
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = contains(["dev"], var.environment)
        metric_name                = "${var.name_prefix}_cf_${rule.key}_waf_mgd_block-cwm-${module.helpers_us.name_suffix_global}"
        sampled_requests_enabled   = contains(["dev"], var.environment)
      }
    }
  }
  # Lifecycle rule required for WAF ACL to be disassociated with Cloudfront when removing WAF or making changes to the WAF ACL that require this resource to be recreated. Otherwise we will encounter error:
  # operation error WAFV2: DeleteWebACL. WAFAssociatedItemException: AWS WAF couldn’t perform the operation because your resource is being used by another resource.
  lifecycle {
    create_before_destroy = true
  }

  tags = local.tags
}

# WAF ACL logging - Any block actions triggered will publish logs - otherwise will be dropped.
resource "aws_wafv2_web_acl_logging_configuration" "waf_logging" {
  count                   = var.enable_waf ? 1 : 0
  log_destination_configs = [aws_cloudwatch_log_group.waf_cw_logs[0].arn]
  resource_arn            = aws_wafv2_web_acl.waf_acl[0].arn
  region                  = "us-east-1"

  logging_filter {
    default_behavior = "DROP"
    filter {
      behavior = "KEEP"
      condition {
        action_condition {
          action = "BLOCK"
        }
      }
      requirement = "MEETS_ANY"
    }
  }
}

# Cloudwatch log group creation WAF
resource "aws_cloudwatch_log_group" "waf_cw_logs" {
  count             = var.enable_waf ? 1 : 0
  name              = "aws-waf-logs-/${var.environment}/${var.name_prefix}_cf" # log files for WAF must begin with "aws-waf-logs-""
  retention_in_days = (var.environment == "prod") ? 365 : 14                   # Standard policy: 365 days in prod, 14 days elsewhere
  kms_key_id        = aws_kms_key.cw_kms_waf_key[0].arn
  region            = "us-east-1"

  tags = merge(
    local.tags,
    { DataClassification = "Confidential Data/Identifying Personal data" } # May contain access logs, which are treated as PII
  )
}

#KMS Key creation and policy
resource "aws_kms_key" "cw_kms_waf_key" {
  count                   = var.enable_waf ? 1 : 0
  description             = "iam kms encryption policy for cloudwatch WAF log files"
  deletion_window_in_days = 7
  region                  = "us-east-1"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "KMS Log group access"
        Effect = "Allow"
        Principal = {
          "AWS" = "arn:aws:iam::${module.helpers_us.account_id}:root"
        },
        Action   = "kms:*",
        Resource = "*"
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "logs.${module.helpers_us.region_name}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ],
        Resource = "*"
        Condition = {
          ArnLike = {
            # Note this is not a reference to the log resource creation above as it will cause a circular dependency
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${module.helpers_us.region_name}:${module.helpers_us.account_id}:log-group:aws-waf-logs-/${var.environment}/${var.name_prefix}_cf*"
          }
        }
      }
    ]
  })

  tags = local.tags
}
resource "aws_kms_alias" "cw_kms_waf_key_alias" {
  count         = var.enable_waf ? 1 : 0
  name          = "alias/${var.name_prefix}_cf_waf_cwlogs-key-${module.helpers_us.name_suffix_global}"
  target_key_id = aws_kms_key.cw_kms_waf_key[0].key_id
  region        = "us-east-1"
}
