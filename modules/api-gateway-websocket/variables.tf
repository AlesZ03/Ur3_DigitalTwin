variable "api_name" {
  description = "Name for the WebSocket API."
  type        = string
}

variable "connect_lambda_invoke_arn" {
  description = "Invoke ARN of the Lambda function for the $connect route."
  type        = string
}

variable "disconnect_lambda_invoke_arn" {
  description = "Invoke ARN of the Lambda function for the $disconnect route."
  type        = string
}

variable "default_lambda_invoke_arn" {
  description = "Invoke ARN of the Lambda function for the $default route."
  type        = string
}

variable "connect_lambda_function_name" {
  description = "Name of the Lambda function for the $connect route."
  type        = string
}

variable "disconnect_lambda_function_name" {
  description = "Name of the Lambda function for the $disconnect route."
  type        = string
}

variable "default_lambda_function_name" {
  description = "Name of the Lambda function for the $default route."
  type        = string
}

variable "tags" {
  description = "A map of tags to assign to the resources."
  type        = map(string)
  default     = {}
}

variable "aws_region" {
  description = "The AWS region where resources are being created."
  type        = string
}
