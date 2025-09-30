
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