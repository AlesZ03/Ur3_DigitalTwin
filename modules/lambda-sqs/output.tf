output "function_name" {
  description = "A Lambda függvény neve"
  value       = aws_lambda_function.function.function_name
}

output "function_arn" {
  description = "A Lambda függvény ARN-je"
  value       = aws_lambda_function.function.arn
}

output "function_invoke_arn" {
  description = "A Lambda függvény invoke ARN-je"
  value       = aws_lambda_function.function.invoke_arn
}

output "role_arn" {
  description = "A Lambda IAM role ARN-je"
  value       = aws_iam_role.lambda_role.arn
}

output "role_name" {
  description = "A Lambda IAM role neve"
  value       = aws_iam_role.lambda_role.name
}

output "log_group_name" {
  description = "A CloudWatch Log Group neve"
  value       = aws_cloudwatch_log_group.lambda_log_group.name
}