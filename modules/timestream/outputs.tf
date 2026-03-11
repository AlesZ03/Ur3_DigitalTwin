output "writer_lambda_arn" {
  value = aws_lambda_function.firehose_to_timestream.arn
}