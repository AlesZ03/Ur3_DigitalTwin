# modules/amplify/main.tf

resource "aws_amplify_app" "robot_control" {
  name       = var.app_name
  repository = var.repository_url

  # Build settings
  build_spec = var.build_spec

  # Environment variables (MAP, not a block!)
  environment_variables = var.environment_variables

  # Custom rules
  dynamic "custom_rule" {
    for_each = var.custom_rules
    content {
      source = custom_rule.value.source
      status = custom_rule.value.status
      target = custom_rule.value.target
    }
  }
 

  # Enable auto branch creation
  enable_auto_branch_creation = var.enable_auto_branch_creation
  enable_branch_auto_build    = var.enable_branch_auto_build
  enable_branch_auto_deletion = var.enable_branch_auto_deletion

  # IAM service role
  iam_service_role_arn = var.iam_service_role_arn

  tags = var.tags
}

# Branch configuration
resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.robot_control.id
  branch_name = var.branch_name

  enable_auto_build = var.enable_branch_auto_build

  # These are allowed as MAP, so this is correct:
  environment_variables = var.branch_environment_variables

  framework = var.framework
  stage     = var.stage
}

# Domain association (optional) 
resource "aws_amplify_domain_association" "main" {
  count = var.domain_name != null ? 1 : 0

  app_id      = aws_amplify_app.robot_control.id
  domain_name = var.domain_name

  sub_domain {
    branch_name = aws_amplify_branch.main.branch_name
    prefix      = var.domain_prefix
  }

  wait_for_verification = var.wait_for_verification
}