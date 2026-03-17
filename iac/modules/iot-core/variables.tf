# modules/iot-core/variables.tf

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "account_id" {
  description = "AWS Account ID"
  type        = string
}

variable "thing_name" {
  description = "Name of the IoT Thing"
  type        = string
}

variable "certs_output_path" {
  description = "Path to save the generated certificates"
  type        = string
}

variable "tags" {
  description = "Common tags for resources"
  type        = map(string)
  default     = {}
}

variable "appsync_api_url" {
  description = "The URL of the AppSync GraphQL API"
  type        = string
}

variable "appsync_api_id" {
  description = "The ID of the AppSync API"
  type        = string
}
variable "iot_endpoint" {
  description = "AWS IoT Endpoint Address"
  type        = string
  default     = null

}