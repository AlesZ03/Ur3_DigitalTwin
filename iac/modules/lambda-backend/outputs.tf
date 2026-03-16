output "lambda_function_arn" {
  description = "The ARN of the UR controller Lambda function."
  value       = aws_lambda_function.ur_control_lambda.arn
}

output "lambda_function_invoke_arn" {
  description = "The Invoke ARN of the UR controller Lambda function."
  value       = aws_lambda_function.ur_control_lambda.invoke_arn
}

output "lambda_function_name" {
  description = "The name of the UR controller Lambda function."
  value       = aws_lambda_function.ur_control_lambda.function_name
}

output "lambda_role_arn" {
  description = "The ARN of the IAM role for the UR controller Lambda function."
  value       = aws_iam_role.ur_controller_lambda_role.arn
}

