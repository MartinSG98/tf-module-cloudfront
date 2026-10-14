# tf-module-cloudfront

Creates a CloudFront distribution in front of an S3 bucket or any other host, with its certificate, DNS records and access logs, and optionally a WAF web ACL and an IP allow list. The distribution itself comes from the community module [terraform-aws-modules/cloudfront/aws](https://registry.terraform.io/modules/terraform-aws-modules/cloudfront/aws/5.0.0) 5.0.0, and this module adds the parts around it:

- **The certificate** comes from [tf-module-acm_cert](https://github.com/MartinSG98/tf-module-acm_cert) in `us-east-1`, with an `EC_prime256v1` key, covers every name in `dns_names` and is validated in `hosted_zone_id`.
- **DNS records** are A aliases to the distribution, one for each name in `dns_names` that ends with the hosted zone's name.
- **Viewers** are redirected from HTTP to HTTPS on every path, with TLS 1.2 (`TLSv1.2_2021`) as the minimum, SNI, compression and IPv6.
- **Access logs** go to `logging_bucket` under the prefix `<environment>/cloudfront/<name_prefix>`.
- **The IP allow list** (`allowed_cidrs`) is a Lambda@Edge viewer-request function that answers 403 to any address outside the list. It is built from `functions/ip_restrict/` with [tf-module-lambda](https://github.com/MartinSG98/tf-module-lambda) in `us-east-1`.
- **The WAF** (`enable_waf`) is described below.

The module uses [tf-module-helpers](https://github.com/MartinSG98/tf-module-helpers) twice, once for the provider's region and once for `us-east-1`, because the WAF, its log group and its KMS key have to be in `us-east-1` while the failover lookup follows the default region. It needs Terraform 1.9 or newer, because some input validations refer to other inputs, the AWS provider 6.x, and the hashicorp/archive provider when `allowed_cidrs` is used.

```hcl
module "site" {
  source = "git::https://github.com/MartinSG98/tf-module-cloudfront.git?ref=1.0.0"

  environment    = var.environment
  name_prefix    = "myapp_web"
  dns_names      = ["www.example.com", "example.com"]
  hosted_zone_id = data.aws_route53_zone.main.zone_id
  logging_bucket = "myapp-logs-example"

  s3_bucket_primary = aws_s3_bucket.site.bucket
  enable_waf        = true

  providers = {
    aws     = aws
    aws.dns = aws.dns
  }

  tags = local.tags
}
```

## Providers

The module needs one extra provider, `aws.dns`, for the account that holds the DNS zone given in `hosted_zone_id`. The zone lookup, the alias records and the certificate's validation records all go through it. Pass `aws` for it when DNS lives in the same account.

## Origins

Give exactly one kind of origin, either `s3_bucket_primary` or `domain_name_origin`. The plan fails if you give both or neither.

- **An S3 bucket** is reached through an origin access identity, which the `origin_access_identities` output exposes for the bucket policy. The distribution allows `GET`, `HEAD` and `OPTIONS` and forwards query strings.
- **Any other host** in `domain_name_origin` is reached over `https-only` by default, with TLS 1.2. The distribution allows every method, and uses the cache policy and origin request policy named in `origin_cache_policy` and `origin_request_policy`. The defaults, `Managed-CachingOptimized` and `Managed-AllViewerExceptHostHeader`, work for S3 website hosting and most other cases, but an application may need a cache policy such as `UseOriginCacheControlHeaders` or `UseOriginCacheControlHeaders-QueryStrings`. S3 website hosting also needs `origin_protocol_policy = "http-only"`.

`s3_bucket_secondary` is meant as a failover origin. The module looks that bucket up in the failover region tf-module-helpers gives for the current region, and builds an origin group that fails over on 500, 502, 503 and 504. As the code stands, `cloudfront.tf` adds the second bucket under the origin key `s3_primary`, so it replaces the primary origin instead of joining it. Fix that key before relying on failover.

All names in `dns_names` must be in the same hosted zone. A name outside it gets no DNS record, and the certificate cannot be validated for it.

## IP allow list

When `allowed_cidrs` is set, every request is checked against the list before it reaches the cache. The function only understands IPv4, so IPv6 clients are refused while the list is set. The function's zip is written to `.lambda_build_cache/` in the root of your stack. It is strongly recommended to allow only trusted IPs in pre-production environments. Turning the list off again later can be [slow and painful](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/lambda-edge-delete-replicas.html), because CloudFront has to remove the function's replicas first.

## WAF

With `enable_waf = true` the distribution gets a web ACL in `us-east-1` that allows by default and runs these rules in order:

1. **Trusted IPs.** Requests from `trusted_cidrs` and `waf_exempt_cidrs` are allowed straight away. `trusted_cidrs` is for permanent exemptions such as office and VPN egress IPs, and `waf_exempt_cidrs` is for temporary ones, such as a pen test that needs to reach the application without the WAF in the way.
2. **Custom block rule groups** from `waf_block_rule_group_arns`, from priority 100.
3. **Custom allow rule groups** from `waf_allow_rule_group_arns`, from priority 200.
4. **The standard AWS managed rule groups**, always on, at priorities 301 to 306: `AWSManagedRulesCommonRuleSet`, `AWSManagedRulesKnownBadInputsRuleSet`, `AWSManagedRulesSQLiRuleSet`, `AWSManagedRulesLinuxRuleSet`, `AWSManagedRulesUnixRuleSet` and `AWSManagedRulesAmazonIpReputationList`. To switch off single rules, list them in `standard_managed_waf_rule_exclusions`, for example `{ AWSManagedRulesSQLiRuleSet = ["SQLi_COOKIE"] }`. Listed rules are overridden to allow.
5. **Extra AWS managed rule groups** from `waf_managed_block_rule_group_names`, from priority 400. The rule block in `waf.tf` reads this input as a map of rule group name to rules to switch off, like `standard_managed_waf_rule_exclusions`, but it is typed `list(string)`, so only the empty default works for now.

Only blocked requests are logged, to the CloudWatch log group `aws-waf-logs-/<environment>/<name_prefix>_cf`, encrypted with its own KMS key and kept for 365 days in `prod` and 14 days elsewhere. CloudWatch metrics and sampled requests for the blocking rules are only turned on in `dev`. A WAF should be in place for every public web-facing service.

Everything to do with WAF lives in `us-east-1`. AWS requires that for web ACLs used with CloudFront ([ListLoggingConfigurations](https://docs.aws.amazon.com/waf/latest/APIReference/API_ListLoggingConfigurations.html)) and for their log groups ([turning on AWS WAF logging](https://repost.aws/knowledge-center/waf-turn-on-logging)), and a KMS key has to be in the same region as the log group it encrypts.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `environment` | `string` | required | Environment the module is used in: `sand`, `dev`, `uat`, `perf`, `stage`, `prod`, `core` or `shared` |
| `name_prefix` | `string` | required | Prefix for all resource names, in lower-case letters, digits and underscores, 12 characters at most |
| `dns_names` | `list(string)` | required | Names the distribution answers on, all in the same hosted zone. The first is the certificate's primary name |
| `hosted_zone_id` | `string` | `null` | Hosted zone for the DNS records and the certificate. Required in practice: the validation rejects null, and the certificate always comes from this zone |
| `logging_bucket` | `string` | required | Name of the S3 bucket for access logs |
| `price_class` | `string` | `"100"` | [Price class](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/PriceClass.html): `100`, `200` or `All` |
| `s3_bucket_primary` | `string` | `null` | S3 bucket to use as the origin |
| `s3_bucket_secondary` | `string` | `null` | Second bucket, in the failover region, meant as a failover origin. Needs `s3_bucket_primary`. See the note above |
| `domain_name_origin` | `string` | `null` | Any host to use as the origin instead of an S3 bucket |
| `origin_protocol_policy` | `string` | `"https-only"` | `https-only` or `http-only` for a `domain_name_origin`. S3 website hosting needs `http-only` |
| `origin_request_policy` | `string` | `"Managed-AllViewerExceptHostHeader"` | Name of the [origin request policy](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-origin-request-policies.html) for a `domain_name_origin` |
| `origin_cache_policy` | `string` | `"Managed-CachingOptimized"` | Name of the [cache policy](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-cache-policies.html) for a `domain_name_origin` |
| `default_root_object` | `string` | `"index.html"` | Object returned when a viewer requests the root URL |
| `allowed_cidrs` | `list(string)` | `[]` | IPv4 CIDRs allowed to use the distribution. Empty allows everyone |
| `enable_waf` | `bool` | `false` | Put a WAF web ACL with the standard rule groups in front of the distribution |
| `trusted_cidrs` | `map(list(string))` | `{}` | Location name to IPv4 CIDRs that are permanently exempt from the WAF rules, for example the `trusted_cidrs` output of tf-module-helpers |
| `waf_exempt_cidrs` | `list(string)` | `[]` | IPv4 CIDRs to exempt from the WAF temporarily, for pen tests and similar |
| `waf_block_rule_group_arns` | `list(string)` | `[]` | Custom rule groups that block |
| `waf_allow_rule_group_arns` | `list(string)` | `[]` | Custom rule groups that allow |
| `waf_managed_block_rule_group_names` | `list(string)` | `[]` | Extra [AWS managed rule groups](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-list.html). See the note in the WAF section |
| `standard_managed_waf_rule_exclusions` | `map(list(string))` | `{}` | Rules to switch off in the standard managed rule groups, keyed by rule group name |
| `account_shortname` | `string` | `null` | Short name for the current account in name suffixes. Falls back to the account ID |
| `tags` | `map(string)` | `{}` | Extra tags for all resources. An `InfraModule` tag is added with `tf-module-cloudfront`, followed by any `InfraModule` value you pass here |

## Outputs

| Name | Description |
|---|---|
| `origin_access_identities` | The distribution's origin access identities, keyed `s3_primary` and `s3_secondary`, for the buckets' policies. The map is wrapped in a list with one element |
| `distribution_id` | ID of the CloudFront distribution |
