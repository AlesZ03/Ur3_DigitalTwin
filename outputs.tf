output "lambda_function_arn" {
  description = "The ARN of the data processor Lambda function."
  value       = module.iot_core_lambda.lambda_function_arn
}

output "lambda_function_name" {
  description = "The name of the data processor Lambda function."
  value       = module.iot_core_lambda.lambda_function_name
}

output "iot_thing_name" {
  description = "The name of the created IoT Thing."
  value       = module.iot_core_lambda.iot_thing_name
}

output "iot_endpoint" {
  description = "The endpoint for the AWS IoT Core service. Copy this to your core-test.py and ur-rtde.py scripts."
  value       = data.aws_iot_endpoint.current.endpoint_address
}