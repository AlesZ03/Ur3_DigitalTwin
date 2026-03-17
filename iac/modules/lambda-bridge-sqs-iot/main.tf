data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
# 1. IAM Role a Híd Lambdának
resource "aws_iam_role" "bridge_lambda_role" {
  name = "${var.bridge_function_name}-role"

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
}

# 2. Alap logolási jogok (CloudWatch)
resource "aws_iam_role_policy_attachment" "bridge_lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.bridge_lambda_role.name
}

# 3. SQS Olvasási jogok (Hogy ki tudja szedni az üzeneteket)
resource "aws_iam_role_policy" "bridge_lambda_sqs_policy" {
  name = "${var.bridge_function_name}-sqs-policy"
  role = aws_iam_role.bridge_lambda_role.id

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

# 4. IoT Core Publikálási jogok (Hogy el tudja küldeni a robotnak)
resource "aws_iam_role_policy" "bridge_lambda_iot_policy" {
  name = "${var.bridge_function_name}-iot-policy"
  role = aws_iam_role.bridge_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iot:Publish"
        ]

        Resource = "arn:aws:iot:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:topic/${var.iot_topic}"
      }
    ]
  })
}

# 5. ZIP fájl készítése a Python kódból
data "archive_file" "bridge_lambda_zip" {
  type        = "zip"
  source_file = var.bridge_lambda_source_file_path
  output_path = var.bridge_lambda_output_zip_path
}

# 6. Maga a Lambda függvény létrehozása
resource "aws_lambda_function" "bridge_function" {
  filename         = data.archive_file.bridge_lambda_zip.output_path
  function_name    = var.bridge_function_name
  role             = aws_iam_role.bridge_lambda_role.arn
  handler          = "iot-core-sqs.lambda_handler"
  source_code_hash = data.archive_file.bridge_lambda_zip.output_base64sha256
  runtime          = "python3.10" # Használd a nálad preferált verziót (pl. python3.9, python3.11)
  timeout          = 10
  memory_size      = 128

  # Környezeti változók átadása a Python kódnak
  environment {
    variables = {
      IOT_ENDPOINT = var.iot_endpoint
      IOT_TOPIC    = var.iot_topic
    }
  }
}

# 7. SQS Trigger beállítása (Ettől fog a Lambda automatikusan lefutni)
resource "aws_lambda_event_source_mapping" "sqs_to_bridge_trigger" {
  event_source_arn = var.sqs_queue_arn
  function_name    = aws_lambda_function.bridge_function.arn
  batch_size       = 10 # Egyszerre max 10 üzenetet vesz ki a sorból
  enabled          = true
}

# 8. CloudWatch Log Group
resource "aws_cloudwatch_log_group" "bridge_lambda_log_group" {
  name              = "/aws/lambda/${var.bridge_function_name}"
  retention_in_days = 14
}