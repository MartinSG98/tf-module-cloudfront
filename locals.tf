locals {
  # Used to tag all resources created by the module
  tags = merge(
    var.tags,
    { "InfraModule" = join(":", compact(["tf-module-cloudfront", lookup(var.tags, "InfraModule", "")])) }
  )


  standard_managed_waf_rules = {

    AWSManagedRulesCommonRuleSet = {
      priority       = 1
      excluded_rules = contains(keys(var.standard_managed_waf_rule_exclusions), "AWSManagedRulesCommonRuleSet") ? var.standard_managed_waf_rule_exclusions["AWSManagedRulesCommonRuleSet"] : []

    },
    AWSManagedRulesKnownBadInputsRuleSet = {
      priority       = 2
      excluded_rules = contains(keys(var.standard_managed_waf_rule_exclusions), "AWSManagedRulesKnownBadInputsRuleSet") ? var.standard_managed_waf_rule_exclusions["AWSManagedRulesKnownBadInputsRuleSet"] : []
    },
    AWSManagedRulesSQLiRuleSet = {
      priority       = 3
      excluded_rules = contains(keys(var.standard_managed_waf_rule_exclusions), "AWSManagedRulesSQLiRuleSet") ? var.standard_managed_waf_rule_exclusions["AWSManagedRulesSQLiRuleSet"] : []
    },
    AWSManagedRulesLinuxRuleSet = {
      priority       = 4
      excluded_rules = contains(keys(var.standard_managed_waf_rule_exclusions), "AWSManagedRulesLinuxRuleSet") ? var.standard_managed_waf_rule_exclusions["AWSManagedRulesLinuxRuleSet"] : []
    },
    AWSManagedRulesUnixRuleSet = {
      priority       = 5
      excluded_rules = contains(keys(var.standard_managed_waf_rule_exclusions), "AWSManagedRulesUnixRuleSet") ? var.standard_managed_waf_rule_exclusions["AWSManagedRulesUnixRuleSet"] : []
    },
    AWSManagedRulesAmazonIpReputationList = {
      priority       = 6
      excluded_rules = contains(keys(var.standard_managed_waf_rule_exclusions), "AWSManagedRulesAmazonIpReputationList") ? var.standard_managed_waf_rule_exclusions["AWSManagedRulesAmazonIpReputationList"] : []
    }
  }
}
