variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "ur_rtde_layer_zip_path" {
  description = "Path to the Lambda Layer zip file for ur-rtde, relative to the root module."
  type        = string
}

variable "ur_controller_lambda_source_path" {
  description = "Path to the source Python file for the UR controller Lambda, relative to the root module."
  type        = string
}

variable "cloud_to_device_queue_arn" {
  description = "ARN of the SQS queue for cloud-to-device commands."
  type        = string
}

variable "cloud_to_device_queue_url" {
  description = "URL of the SQS queue for cloud-to-device commands."
  type        = string
}

variable "common_tags" {
  description = "Common tags to apply to all resources."
  type        = map(string)
  default     = {}
}

