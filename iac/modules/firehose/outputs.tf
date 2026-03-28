output "firehose_arn" {
  value = aws_kinesis_firehose_delivery_stream.telemetry_stream.arn
}
output "bucket_name" {
  value = module.s3_robot_data.bucket_name
}
output "bucket_arn" {
  value = module.s3_robot_data.bucket_arn

}