variable "queue_name" {
  type        = string
  description = "SQS várólista neve"
}

variable "visibility_timeout_seconds" {
  type        = number
  default     = 30
  description = "Üzenet láthatósági időtúllépés másodpercben"
}

variable "message_retention_seconds" {
  type        = number
  default     = 345600  // 4 nap
  description = "Üzenet megőrzési idő másodpercben"
}

variable "max_message_size" {
  type        = number
  default     = 262144  // 256 KB
  description = "Maximum üzenet méret bájtokban"
}

variable "delay_seconds" {
  type        = number
  default     = 0
  description = "Üzenet késleltetés másodpercben"
}

variable "receive_wait_time_seconds" {
  type        = number
  default     = 0
  description = "Long polling idő másodpercben"
}

variable "enable_dlq" {
  type        = bool
  default     = false
  description = "Dead Letter Queue engedélyezése"
}

variable "max_receive_count" {
  type        = number
  default     = 3
  description = "Maximum fogadási próbálkozások száma DLQ előtt"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Resource tags"
}

// Dead Letter Queue
resource "aws_sqs_queue" "dlq" {
  count = var.enable_dlq ? 1 : 0
  
  name                      = "${var.queue_name}-dlq"
  message_retention_seconds = 1209600  // 14 nap
  
  tags = merge(var.tags, {
    Type = "DeadLetterQueue"
  })
}

// Fő SQS várólista
resource "aws_sqs_queue" "main" {
  name                       = var.queue_name
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds
  max_message_size           = var.max_message_size
  delay_seconds              = var.delay_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  
  redrive_policy = var.enable_dlq ? jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[0].arn
    maxReceiveCount     = var.max_receive_count
  }) : null
  
  tags = var.tags
}

// Outputs
output "queue_arn" {
  value       = aws_sqs_queue.main.arn
  description = "SQS várólista ARN"
}

output "queue_url" {
  value       = aws_sqs_queue.main.url
  description = "SQS várólista URL"
}

output "queue_name" {
  value       = aws_sqs_queue.main.name
  description = "SQS várólista neve"
}

output "dlq_arn" {
  value       = var.enable_dlq ? aws_sqs_queue.dlq[0].arn : null
  description = "Dead Letter Queue ARN"
}

// === variables.tf ===
variable "aws_region" {
  type        = string
  default     = "eu-central-1"
  description = "AWS régió"
}

variable "project_name" {
  type        = string
  default     = "robot-digital-twin"
  description = "Projekt név prefix"
}

variable "common_tags" {
  type = map(string)
  default = {
    Project     = "Robot Digital Twin"
    Environment = "production"
    ManagedBy   = "Terraform"
  }
}
