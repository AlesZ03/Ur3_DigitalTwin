# modules/amplify/variables.tf

variable "app_name" {
  description = "Az Amplify alkalmazás neve"
  type        = string
}

variable "repository_url" {
  description = "Git repository URL (GitHub/GitLab/etc.)"
  type        = string
  default     = null
}

variable "build_spec" {
  description = "Build specification YAML"
  type        = string
  default     = null
}

variable "environment_variables" {
  description = "Környezeti változók az Amplify app számára"
  type        = map(string)
  default     = {}
}

variable "branch_environment_variables" {
  description = "Branch-specifikus környezeti változók"
  type        = map(string)
  default     = {}
}

variable "custom_rules" {
  description = "Custom redirect/rewrite szabályok"
  type = list(object({
    source = string
    status = string
    target = string
  }))
  default = []
}

variable "enable_auto_branch_creation" {
  description = "Auto branch creation engedélyezése"
  type        = bool
  default     = false
}

variable "enable_branch_auto_build" {
  description = "Branch auto build engedélyezése"
  type        = bool
  default     = true
}

variable "enable_branch_auto_deletion" {
  description = "Branch auto deletion engedélyezése"
  type        = bool
  default     = false
}

variable "iam_service_role_arn" {
  description = "IAM service role ARN az Amplify számára"
  type        = string
  default     = null
}

variable "branch_name" {
  description = "Git branch neve"
  type        = string
  default     = "main"
}

variable "framework" {
  description = "Frontend framework (React, Vue, Angular, stb.)"
  type        = string
  default     = "React"
}

variable "stage" {
  description = "Deployment stage"
  type        = string
  default     = "PRODUCTION"
}

variable "domain_name" {
  description = "Custom domain név (opcionális)"
  type        = string
  default     = null
}

variable "domain_prefix" {
  description = "Domain prefix (pl. www, app)"
  type        = string
  default     = ""
}

variable "wait_for_verification" {
  description = "Várakozás a domain verifikációra"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tagek az Amplify erőforrásokhoz"
  type        = map(string)
  default     = {}
}

variable "access_token" {
  description = "GitHub Personal Access Token for Amplify"
  type        = string
  sensitive   = true
}