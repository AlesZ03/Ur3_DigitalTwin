variable "project_name" {
  description = "A projekt neve"
  type        = string
}

variable "lambda_source_path" {
  description = "A Python Lambda fájl relatív útvonala a gyökérkönyvtárhoz képest"
  type        = string
}

variable "tags" {
  description = "Általános tagek az erőforrásokhoz"
  type        = map(string)
  default     = {}
}