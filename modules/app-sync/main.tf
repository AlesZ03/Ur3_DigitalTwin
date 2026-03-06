# modules/app-sync/main.tf

resource "aws_appsync_graphql_api" "ur3_api" {
  name                = "${var.project_name}-api"
  authentication_type = "API_KEY" 
  schema              = file(var.schema_path)

  additional_authentication_provider {
    authentication_type = "AWS_IAM"
  }

  log_config {
    cloudwatch_logs_role_arn = aws_iam_role.appsync_logging_role.arn
    field_log_level          = "ALL"
    exclude_verbose_content  = false
  }

  tags = var.tags
}

resource "aws_appsync_api_key" "ur3_api_key" {
  api_id = aws_appsync_graphql_api.ur3_api.id

}

resource "aws_iam_role" "appsync_role" {
  name = "${var.project_name}-appsync-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "appsync.amazonaws.com"
      }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role" "appsync_logging_role" {
  name = "${var.project_name}-appsync-logging-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "appsync.amazonaws.com"
      }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "appsync_logging_policy" {
  name = "${var.project_name}-appsync-logging-policy"
  role = aws_iam_role.appsync_logging_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = [
          "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:/aws/appsync/apis/${aws_appsync_graphql_api.ur3_api.id}",
          
          "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:/aws/appsync/apis/${aws_appsync_graphql_api.ur3_api.id}:*"
        ]
      }
    ]
  })
}

resource "aws_appsync_datasource" "none_ds_for_mutations" {
  api_id           = aws_appsync_graphql_api.ur3_api.id
  name             = "NoneDataSourceForMutations"
  type             = "NONE"
  service_role_arn = aws_iam_role.appsync_role.arn
}

resource "aws_appsync_resolver" "publish_shadow_update_resolver" {
  api_id      = aws_appsync_graphql_api.ur3_api.id
  type        = "Mutation"
  field       = "publishShadowUpdate"
  data_source = aws_appsync_datasource.none_ds_for_mutations.name

  request_template = <<EOF
  {
    "version": "2018-05-29",
    "payload": $util.toJson($context.arguments)
  }
  EOF

  response_template = "$util.toJson($context.result)"
}
  