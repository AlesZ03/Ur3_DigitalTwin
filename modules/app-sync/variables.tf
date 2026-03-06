# modules/app-sync/variables.tf

variable "project_name" {
  description = "A projekt neve, erőforrás nevek prefixeként használva."
  type        = string
}

variable "aws_region" {
  description = "Az AWS régió, ahol az erőforrások létrehozásra kerülnek."
  type        = string
}

variable "account_id" {
  description = "Az AWS fiók azonosítója."
  type        = string
}

variable "schema_path" {
  description = "Az AppSync GraphQL séma fájl elérési útja."
  type        = string
}

variable "tags" {
  description = "Közös tagek az erőforrásokhoz."
  type        = map(string)
  default     = {}
}
