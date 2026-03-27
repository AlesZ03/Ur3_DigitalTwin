variable "project_name" {
  type = string
}
variable "account_id" {
  type = string
}
variable "aws_region" {
  type = string
}
variable "tags" {
  type    = map(string)
  default = {}
}

variable "lambda_writer_arn" {
  description = "A DynamoDB író Lambda ARN-je"
  type        = string
}

