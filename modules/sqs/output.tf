
// Outputs
output "queue_arn" {
  value       = aws_sqs_queue.main.arn
  description = "SQS várólista ARN"
}

output "queue_url" {
  value       = aws_sqs_queue.main.url
  description = "SQS várólista URL"
}

output "queue_name" {
  value       = aws_sqs_queue.main.name
  description = "SQS várólista neve"
}

output "dlq_arn" {
  value       = var.enable_dlq ? aws_sqs_queue.dlq[0].arn : null
  description = "Dead Letter Queue ARN"
}
