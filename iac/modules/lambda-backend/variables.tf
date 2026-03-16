# modules/lambda-backend/variables.tf

variable "project_name" {
  type        = string
  description = "A projekt neve"
}

variable "common_tags" {
  type        = map(string)
  description = "Közös tagek az erőforrásokhoz"
}

variable "ur_rtde_layer_zip_path" {
  type        = string
  description = "A UR RTDE layer ZIP fájl relatív elérési útja a root-tól"
}

variable "ur_controller_lambda_source_path" {
  type        = string
  description = "A UR kontroller Lambda forráskódjának relatív elérési útja"
}

variable "cloud_to_device_queue_arn" {
  type        = string
  description = "A Cloud to Device SQS sor ARN-je"
}

variable "cloud_to_device_queue_url" {
  type        = string
  description = "A Cloud to Device SQS sor URL-je"
}