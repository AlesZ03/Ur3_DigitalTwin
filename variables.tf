
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

variable "ur_rtde_layer_zip_path" {
  description = "A `ur-rtde` library-t tartalmazó Lambda Layer ZIP fájl elérési útja."
  type        = string
  default     = "lambda/layers/ur-rtde-layer.zip"
}

variable "ur_controller_lambda_source_path" {
  description = "A robotot vezérlő Lambda forráskódjának elérési útja."
  type        = string
  default     = "lambda/backend/controller.py"
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

# GitHub integration
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

}

variable "websocket_dynamodb_table" {
  description = "Name for the DynamoDB table storing WebSocket connections."
  type        = string
  default     = "robot-websocket-connections"
}
variable "iot_bridge_lambda_arn" {
  description = "Az IoT Bridge Lambda függvény ARN azonosítója"
  type        = string
  default     = null
}

variable "iot_endpoint" {
  description = "AWS IoT Endpoint Address"
  type        = string
  default     = null
}