variable "thing_name" {
  description = "The name of the IoT Thing."
  type        = string
  default     = "UR3-Robot-001"
}

variable "thing_type_name" {
  description = "The name of the IoT Thing Type."
  type        = string
  default     = "UR3RobotType"
}

variable "random_suffix" {
  description = "A random string to ensure unique resource names."
  type        = string
}
variable "lambda_zip_path" {
  description = "A Lambda zip fájl elérési útja"
  type        = string
}

variable "lambda_execution_role_arn" {
  description = "ARN of the IAM role for the Lambda function."
  type        = string
}

variable "lambda_source_file_path" {
  description = "Path to the Python source file for the Lambda."
  type        = string
}

variable "lambda_function_name" {
  description = "The name for the data processing Lambda function."
  type        = string
  default     = "ur3-data-processor"
}

variable "lambda_handler" {
  description = "The handler for the Lambda function."
  type        = string
  default     = "lambda_function.lambda_handler"
}

variable "lambda_runtime" {
  description = "The runtime for the Lambda function."
  type        = string
  default     = "python3.9"
}

variable "websocket_api_endpoint" {
  description = "The invoke URL for the WebSocket API Gateway."
  type        = string
}

variable "websocket_connections_dynamodb_table_name" {
  description = "The name of the DynamoDB table for WebSocket connections."
  type        = string
}

variable "aws_account_id" {
  description = "The AWS Account ID."
  type        = string
}

variable "certs_output_path" {
  description = "The local directory path to store the generated IoT certificates."
  type        = string
}

variable "telemetry_topic" {
  description = "The IoT topic for robot telemetry."
  type        = string
  default     = "ur3/robot/telemetry"
}

variable "commands_topic" {
  description = "The IoT topic for robot commands."
  type        = string
  default     = "ur3/robot/commands"
}