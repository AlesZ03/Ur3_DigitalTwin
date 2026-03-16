output "firehose_arn" {
  value = aws_kinesis_firehose_delivery_stream.telemetry_stream.arn
}