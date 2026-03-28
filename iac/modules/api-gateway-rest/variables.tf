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




variable "project_name" {
  description = "Projekt neve"
  type        = string
  default     = null
}
variable "tags" {
  description = "Tagek az API Gateway erőforrásokhoz"
  type        = map(string)
  default     = {}
}
variable "s3_bucket_name" {
  description = "S3 bucket neve"
  type        = string
  default     = null

}
variable "firehose_s3_bucket_name" {
  description = "S3 bucket neve(firehose)"
  type        = string
  default     = null

}
variable "telemetry_table_name" {
  description = "A DynamoDB telemetria tábla neve"
  type        = string
}
variable "lambda_execution_role_arn" {
  description = "Lambda függvény végrehajtási szerepkör ARN-je"
  type        = string
  default     = null

}
variable "command_queue_url" {
  description = "SQS parancs várólista URL-je"
  type        = string
  default     = null

}