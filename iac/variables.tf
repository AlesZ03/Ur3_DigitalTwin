variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "eu-central-1" # (Módosítottam eu-central-1-re, mert a Python kódod is Frankfurtot használt!)
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "ur3-digital-twin-eu"
}

variable "alert_email" {
  description = "Email cím riasztásokhoz (opcionális)"
  type        = string
  default    = ""
}

# --- S3 Archiválási változók ---
variable "s3_versioning_enabled" {
  description = "S3 verziókezelés engedélyezése"
  type        = bool
  default     = true
}

variable "s3_encryption_algorithm" {
  description = "S3 titkosítási algoritmus"
  type        = string
  default     = "AES256"
}

# --- Közös tagek (Metadata) ---
variable "common_tags" {
  description = "Közös tagek az összes erőforráshoz"
  type        = map(string)
  default = {
    Project     = "robot-data-pipeline"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

# --- AWS Amplify & CI/CD (GitHub) Változók ---
variable "amplify_branch_name" {
  description = "Amplify branch neve"
  type        = string
  default     = "main"
}

variable "github_repo_owner" {
  description = "GitHub repo owner (username vagy organization)"
  type        = string
  default     = "AlesZ03"
}

variable "github_repo_name" {
  description = "GitHub repo name (pl. Ur3_DigitalTwin)"
  type        = string
  default     = "Ur3_DigitalTwin_deploy"
}

variable "github_personal_access_token" {
  description = "GitHub personal access token (scope: repo, admin:repo_hook)"
  type        = string
  sensitive   = true
  # Soha ne adj meg itt fix értéket (hardcode)! Terraform Cloud-ban vagy lokális .tfvars-ból add át!
}