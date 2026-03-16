# modules/amplify/main.tf


resource "aws_iam_role" "amplify_role" {
  name = "${var.app_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "amplify.amazonaws.com"
      }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "amplify_backend" {
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess-Amplify"
  role       = aws_iam_role.amplify_role.name
}


resource "aws_amplify_app" "robot_control" {
  name         = var.app_name
  repository   = var.repository_url
  access_token = var.access_token 
  platform     = "WEB"            

  build_spec            = var.build_spec
  environment_variables = var.environment_variables

  dynamic "custom_rule" {
    for_each = var.custom_rules
    content {
      source = custom_rule.value.source
      status = custom_rule.value.status
      target = custom_rule.value.target
    }
  }

  iam_service_role_arn = aws_iam_role.amplify_role.arn # Belsőleg hivatkozunk a fenti role-ra!

  tags = var.tags
}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.robot_control.id
  branch_name = var.branch_name

  enable_auto_build = var.enable_branch_auto_build

  environment_variables = var.branch_environment_variables
  framework             = var.framework
  stage                 = var.stage
}

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