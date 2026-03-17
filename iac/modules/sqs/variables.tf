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
  default     = 345600 // 4 nap
  description = "Üzenet megőrzési idő másodpercben"
}

variable "max_message_size" {
  type        = number
  default     = 262144 // 256 KB
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