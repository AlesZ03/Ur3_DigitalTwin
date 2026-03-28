output "firehose_arn" {
  value = aws_kinesis_firehose_delivery_stream.telemetry_stream.arn
}
output "bucket_name" {
  value = aws_s3_bucket.telemetry_bucket.bucket_domain_name
}
output "bucket_arn" {
  value = aws_s3_bucket.telemetry_bucket.arn


}