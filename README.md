# tf-module-cloudfront

This module creates a standard CloudFront CDN using either S3 or another hostname as its origin. Failover S3 origin is possible by passing through a second bucket.

## Notes

All WAF related resources are required to be in us-east-1 region.

References:

* [AWS WAF ListLoggingConfigurations](https://docs.aws.amazon.com/waf/latest/APIReference/API_ListLoggingConfigurations.html) states: To work with CloudFront, you must also specify the Region US East (N. Virginia)
* [How do I turn on AWS WAF logging and send logs to CloudWatch](https://repost.aws/knowledge-center/waf-turn-on-logging) states: For global web ACLs that you associate to Amazon CloudFront, the log group must be in the US East (N. Virginia) Region.
* KMS resources need to be in the same region as the log group.
* helpers_us.tf is required for the KMS key policy, as the standard helpers instance follows the provider's default region.

## Providers

This module needs 1 extra provider:
* `aws.dns`: The account where the DNS zone(s) (see `dns_names` and `hosted_zone_id`) reside.

## Inputs

* `environment`: The name of the environment in which this module is being invoked.
* `name_prefix`: Used for naming all resources created.
* `account_shortname`: Optional short name for the current account, used in resource name suffixes.
* `tags`: Additional tags to be applied to all resources created by this module.
* `dns_names`: DNS names to respond on. All names must be in the SAME DNS zone, or DNS entries and SSL cert for them won't be created, so it won't work properly.
* `price_class`: The price class to use. https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/PriceClass.html
* `s3_bucket_primary`: The primary S3 bucket to use for the distribution origin.
* `s3_bucket_secondary`: An optional secondary S3 bucket to use for the distribution origin. The bucket must be in the designated failover region for the main region.
* `domain_name_origin`: A host to use as origin instead of `s3_bucket_primary`/`s3_bucket_secondary`
* `origin_protocol_policy`: Protocol for origin (`domain_name_origin`) access - should be "https-only" (the default) unless you are sure you know otherwise. S3 website hosting requires "http-only".
* `origin_request_policy`: Name of the [origin request policy](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/controlling-origin-requests.html) for origin (`domain_name_origin`) access - defaults to "[Managed-AllViewerExceptHostHeader](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-origin-request-policies.html#managed-origin-request-policy-all-viewer-except-host-header)" (works with S3 website hosting and most other anticipated use cases).
* `origin_cache_policy`: Name of the [origin cache policy](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-cache-policies.html) for origin (`domain_name_origin`) - defaults to "[Managed-CachingOptimized](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-cache-policies.html#managed-cache-caching-optimized)" (works with S3 website hosting but may need changing to e.g. "UseOriginCacheControlHeaders" or "UseOriginCacheControlHeaders-QueryStrings" for applications).
* `logging_bucket`: The name of the S3 bucket to use for storage of access logs.
* `hosted_zone_id`: The hosted zone ID in which the dns_name will be. If not passed - note the resources not created below.
* `default_root_object`: The object CloudFront returns when an end user requests the root URL.
* `allowed_cidrs`: List of CIDRs which may access the distribution. Default is to allow all traffic. It is strongly recommended to allow only trusted IPs in pre-production environments. Note that disabling this after it's previously been enabled may be [slow and painful](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/lambda-edge-delete-replicas.html).
* `enable_waf`: enable an AWS web application firewall containing default rulesets. Should be present for all public web facing services.
* `trusted_cidrs`: Map of location name to list of trusted IPv4 CIDRs which are permanently exempt from the WAF rules (e.g. your office and VPN egress IPs).
* `waf_allow_rule_group_arns`: custom allow rule groups can be submitted if required
* `waf_block_rule_group_arns`: custom block rule groups can be submitted if required
* `waf_managed_block_rule_group_names`: Additional [AWS managed block rule groups](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-list.html) to use, with a list of rules in the rule group to *disable*, in addition to the standard rule groups we always use (see local.standard_managed_waf_rules). Format same as `standard_managed_waf_rule_exclusions`.
* `waf_exempt_cidrs`: CIDRs which are exempted from the WAF checks. Use this TEMPORARILY for pen tests and similar, where you wish to test the application directly, bypassing WAF. For permanent exemptions use `trusted_cidrs` instead.
* `standard_managed_waf_rule_exclusions`: Specify the AWS WAF rules you want to *disable* from a rule group. Example { AWSManagedRulesSQLiRuleSet = ["SQLi_COOKIE"] } to disable the SQLi_COOKIE rule in the AWSManagedRulesSQLiRuleSet rule group.

## Outputs

* `origin_access_identities`: A map of the origin access identities, used for creating bucket policies
