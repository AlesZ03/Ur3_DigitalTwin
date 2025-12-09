# modules/api-gateway-rest/variables.tf

variable "api_name" {
  description = "API Gateway neve"
  type        = string
}

variable "api_description" {
  description = "API Gateway leírása"
  type        = string
  default     = "REST API for robot logs"
}

variable "stage_name" {
  description = "Stage neve"
  type        = string
  default     = "prod"
}

variable "lambda_invoke_arn" {
  description = "Lambda függvény invoke ARN-je"
  type        = string
}

variable "lambda_function_name" {
  description = "Lambda függvény neve (logs olvasáshoz)"
  type        = string
}

variable "command_lambda_invoke_arn" {
  description = "Command Lambda függvény invoke ARN-je"
  type        = string
}

variable "command_lambda_function_name" {
  description = "Command Lambda függvény neve"
  type        = string
}

variable "tags" {
  description = "Tagek az API Gateway erőforrásokhoz"
  type        = map(string)
  default     = {}
}