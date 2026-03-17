# modules/lambda/main.tf

data "aws_caller_identity" "current" {}


# IAM role a Lambda függvényhez
resource "aws_iam_role" "lambda_role" {
  name = "${var.function_name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# Basic execution role
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_role.name
}

# SQS policy
resource "aws_iam_role_policy" "lambda_sqs_policy" {
  name = "${var.function_name}-sqs-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = var.sqs_queue_arn
      }
    ]
  })
}

# S3 policy
resource "aws_iam_role_policy" "lambda_s3_policy" {
  name = "${var.function_name}-s3-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetObject"
        ]
        Resource = "${var.s3_bucket_arn}/*"
      }
    ]
  })
}

# ZIP fájl létrehozása a forráskódból
data "archive_file" "lambda_zip" {
  type = "zip"
  source {
    content  = file(var.lambda_source_file_path)
    filename = "index.py" # A handler 'index.handler', ezért a fájlnévnek 'index.py'-nak kell lennie
  }
  output_path = var.lambda_output_zip_path
}

# Lambda függvény
resource "aws_lambda_function" "function" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = var.function_name
  role             = aws_iam_role.lambda_role.arn
  handler          = var.handler
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = var.runtime
  timeout          = var.timeout
  memory_size      = var.memory_size

  environment {
    variables = merge(
      {
        S3_BUCKET_NAME = var.s3_bucket_name
      },
      var.environment_variables
    )
  }

  tags = var.tags
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

# Event source mapping - SQS trigger
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = var.sqs_queue_arn
  function_name    = aws_lambda_function.function.arn
  batch_size       = var.sqs_batch_size
  enabled          = var.sqs_trigger_enabled

  scaling_config {
    maximum_concurrency = var.maximum_concurrency
  }
}

