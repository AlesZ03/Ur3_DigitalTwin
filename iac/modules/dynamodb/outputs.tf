output "writer_lambda_arn" {
  description = "A DynamoDB író Lambda ARN-je"
  value       = aws_lambda_function.dynamo_writer.arn
}

output "dynamodb_table_name" {
  description = "A DynamoDB tábla neve"
  value       = aws_dynamodb_table.telemetry_db.name
}