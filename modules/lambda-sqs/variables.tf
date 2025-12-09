variable "function_name" {
  description = "A Lambda függvény neve"
  type        = string
}

variable "lambda_zip_path" {
  description = "A Lambda zip fájl elérési útja"
  type        = string
}

variable "handler" {
  description = "Lambda handler (pl. index.handler)"
  type        = string
  default     = "index.handler"
}

variable "runtime" {
  description = "Lambda runtime (pl. python3.11)"
  type        = string
  default     = "python3.11"
}

variable "timeout" {
  description = "Lambda timeout másodpercben"
  type        = number
  default     = 60
}

variable "memory_size" {
  description = "Lambda memória mérete MB-ban"
  type        = number
  default     = 128
}

variable "sqs_queue_arn" {
  description = "Az SQS queue ARN-je"
  type        = string
}

variable "sqs_batch_size" {
  description = "SQS batch méret"
  type        = number
  default     = 10
}

variable "sqs_trigger_enabled" {
  description = "SQS trigger engedélyezése"
  type        = bool
  default     = true
}

variable "maximum_concurrency" {
  description = "Lambda maximum párhuzamosság"
  type        = number
  default     = 2
}

variable "s3_bucket_name" {
  description = "Az S3 bucket neve"
  type        = string
}

variable "s3_bucket_arn" {
  description = "Az S3 bucket ARN-je"
  type        = string
}

variable "environment_variables" {
  description = "Lambda környezeti változók"
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  description = "CloudWatch Logs megőrzési idő napokban"
  type        = number
  default     = 7
}

variable "tags" {
  description = "Tagek a Lambda erőforrásokhoz"
  type        = map(string)
  default     = {}
}