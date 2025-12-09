
variable "aws_region" {
  description = "AWS region where resources will be created"
  type        = string
  default     = "us-east-1"
}

variable "glb_file_path" {
  description = "Path to the GLB file for the UR3 robot model"
  type        = string
  default     = "./models/ur3_robot.glb"
}

variable "workspace_name" {
  description = "Name of the TwinMaker workspace"
  type        = string
  default     = "ur3-workspace-terraform"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "ur3-digital-twin"
}





variable "alert_email" {
  type        = string
  default     = "balazsvajk2003@gmail.com"
  description = "Email cím riasztásokhoz (opcionális)"
}





# S3 változók
variable "s3_bucket_name" {
  description = "Az S3 bucket neve"
  type        = string
  default     = "robot-data-storage-123"
}

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

# Lambda változók
variable "lambda_function_name" {
  description = "Lambda függvény neve"
  type        = string
  default     = "robot-data-processor"
}

variable "lambda_zip_path" {
  description = "Lambda zip fájl elérési útja"
  type        = string
  default     = "./lambda/sqs/lambda_function.zip"
}

variable "lambda_handler" {
  description = "Lambda handler"
  type        = string
  default     = "index.handler"
}

variable "lambda_runtime" {
  description = "Lambda runtime"
  type        = string
  default     = "python3.11"
}

variable "lambda_timeout" {
  description = "Lambda timeout másodpercben"
  type        = number
  default     = 60
}

variable "lambda_memory_size" {
  description = "Lambda memória méret MB-ban"
  type        = number
  default     = 128
}

variable "lambda_sqs_batch_size" {
  description = "SQS batch méret a Lambda triggerhez"
  type        = number
  default     = 10
}

variable "lambda_sqs_trigger_enabled" {
  description = "SQS trigger engedélyezése"
  type        = bool
  default     = true
}

variable "lambda_max_concurrency" {
  description = "Lambda maximum párhuzamosság"
  type        = number
  default     = 2
}

variable "lambda_environment_variables" {
  description = "További Lambda környezeti változók"
  type        = map(string)
  default     = {}
}

variable "lambda_log_retention_days" {
  description = "Lambda log megőrzési idő napokban"
  type        = number
  default     = 7
}

# SQS ARN (a meglévő SQS modulból jön)
variable "sqs_queue_arn" {
  description = "Az SQS queue ARN-je"
  type        = string
   default     = "" 
}

# Közös tagek
variable "common_tags" {
  description = "Közös tagek az összes erőforráshoz"
  type        = map(string)
  default = {
    Project     = "robot-data-pipeline"
    Environment = "production"
    ManagedBy   = "terraform"
  }
}


# Amplify változók
variable "github_repo_url" {
  description = "GitHub repository URL az Amplify deploy-hoz (opcionális)"
  type        = string
  default     = null
}

variable "amplify_branch_name" {
  description = "Amplify branch neve"
  type        = string
  default     = "main"
}