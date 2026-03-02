output "lambda_function_arn" {
  description = "The ARN of the data processor Lambda function."
  value       = aws_lambda_function.ur3_data_processor.arn
}

output "lambda_function_name" {
  description = "The name of the data processor Lambda function."
  value       = aws_lambda_function.ur3_data_processor.function_name
}

output "iot_thing_name" {
  description = "The name of the created IoT Thing."
  value       = aws_iot_thing.ur3_robot_thing.name
}