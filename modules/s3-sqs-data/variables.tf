# modules/s3/variables.tf

variable "bucket_name" {
  description = "Az S3 bucket neve"
  type        = string
}

variable "versioning_enabled" {
  description = "S3 bucket verziókezelés engedélyezése"
  type        = bool
  default     = true
}

variable "encryption_algorithm" {
  description = "Titkosítási algoritmus (AES256 vagy aws:kms)"
  type        = string
  default     = "AES256"
}

variable "lifecycle_rules" {
  description = "S3 bucket lifecycle szabályok"
  type = list(object({
    id              = string
    status          = string
    prefix          = string
    expiration_days = optional(number)
    transitions = optional(list(object({
      days          = number
      storage_class = string
    })))
  }))
  default = null
}

variable "tags" {
  description = "Tagek az S3 bucket-hez"
  type        = map(string)
  default     = {}
}