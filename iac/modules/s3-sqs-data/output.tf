# modules/s3/outputs.tf

output "bucket_id" {
  description = "Az S3 bucket ID-ja"
  value       = aws_s3_bucket.robot_data_storage.id
}

output "bucket_arn" {
  description = "Az S3 bucket ARN-je"
  value       = aws_s3_bucket.robot_data_storage.arn
}

output "bucket_name" {
  description = "Az S3 bucket neve"
  value       = aws_s3_bucket.robot_data_storage.bucket
}

output "bucket_domain_name" {
  description = "Az S3 bucket domain neve"
  value       = aws_s3_bucket.robot_data_storage.bucket_domain_name
}

output "bucket_regional_domain_name" {
  description = "Az S3 bucket regionális domain neve"
  value       = aws_s3_bucket.robot_data_storage.bucket_regional_domain_name
}