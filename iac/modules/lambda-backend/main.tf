# Lambda Layer for ur-rtde library
resource "aws_lambda_layer_version" "ur_rtde_layer" {
  filename            = "${path.root}/${var.ur_rtde_layer_zip_path}"
  layer_name          = "ur-rtde-library"
  compatible_runtimes = ["python3.10"]
  description         = "Lambda Layer containing the ur-rtde Python library"
}

# ZIP file for the UR controller Lambda
data "archive_file" "ur_controller_lambda" {
  type        = "zip"
  output_path = "${path.root}/lambda-dist/ur-controller.zip"
  source {
    content  = file("${path.root}/${var.ur_controller_lambda_source_path}")
    filename = "index.py" # Assuming the handler is index.handler
  }
}

# IAM role for the UR controller Lambda
resource "aws_iam_role" "ur_controller_lambda_role" {
  name = "${var.project_name}-ur-controller-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })

  tags = var.common_tags
}

# Basic execution policy for the controller Lambda
resource "aws_iam_role_policy_attachment" "ur_controller_lambda_basic" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.ur_controller_lambda_role.name
}

# Policy to allow sending commands to the SQS queue
resource "aws_iam_role_policy" "ur_controller_lambda_policy" {
  name = "${var.project_name}-ur-controller-sqs-policy"
  role = aws_iam_role.ur_controller_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage", "sqs:GetQueueAttributes", "sqs:GetQueueUrl"]
        Resource = var.cloud_to_device_queue_arn
      }
    ]
  })
}

# Lambda function for UR Robot Controller
resource "aws_lambda_function" "ur_control_lambda" {
  filename         = data.archive_file.ur_controller_lambda.output_path
  function_name    = "${var.project_name}-ur-robot-controller"
  role             = aws_iam_role.ur_controller_lambda_role.arn
  handler          = "index.handler"
  runtime          = "python3.10"
  timeout          = 60
  source_code_hash = data.archive_file.ur_controller_lambda.output_base64sha256

  layers = [aws_lambda_layer_version.ur_rtde_layer.arn]

  environment {
    variables = {
      COMMAND_QUEUE_URL = var.cloud_to_device_queue_url
    }
  }

  tags = var.common_tags
}

# CloudWatch Log Group for the controller Lambda
resource "aws_cloudwatch_log_group" "ur_control_lambda" {
  name              = "/aws/lambda/${aws_lambda_function.ur_control_lambda.function_name}"
  retention_in_days = 7

  tags = var.common_tags
}

