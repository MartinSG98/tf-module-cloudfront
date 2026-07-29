output "origin_access_identities" {
  value       = module.cloudfront.*.cloudfront_origin_access_identities
  description = "The Cloudfront distribution's origin access identities, used to allow access to the origin S3 bucket in the bucket policy"
}

output "distribution_id" {
  value       = module.cloudfront.cloudfront_distribution_id
  description = "The Cloudfront distribution's ID"
}
