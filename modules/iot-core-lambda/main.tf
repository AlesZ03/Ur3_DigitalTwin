# Lambda ZIP fájl
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/iot-core_to_ws.zip" # Ideiglenes fájl a modulon belül
  source {
    content  = file(var.lambda_source_file_path)
    filename = "lambda_function.py" # A handler `lambda_function.lambda_handler`, ezért a fájlnévnek egyeznie kell
  }
}

# Lambda Function
resource "aws_lambda_function" "ur3_data_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = var.lambda_function_name
  role             = var.lambda_execution_role_arn
  handler          = var.lambda_handler
  runtime          = var.lambda_runtime
  timeout          = 30
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      WEBSOCKET_API_ENDPOINT = replace(var.websocket_api_endpoint, "wss://", "https://")
      DYNAMODB_TABLE_NAME    = var.websocket_connections_dynamodb_table_name
    }
  }
}

# Lambda permission for IoT
resource "aws_lambda_permission" "allow_iot" {
  statement_id  = "AllowExecutionFromIoT"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ur3_data_processor.function_name
  principal     = "iot.amazonaws.com"
  source_arn    = aws_iot_topic_rule.ur3_data_rule.arn
}

# Lambda permission for TwinMaker
resource "aws_lambda_permission" "allow_twinmaker" {
  statement_id   = "AllowExecutionFromTwinMaker"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.ur3_data_processor.function_name
  principal      = "iottwinmaker.amazonaws.com"
  source_account = var.aws_account_id
}

# IoT Thing Type
resource "aws_iot_thing_type" "ur3_robot_thing_type" {
  name = var.thing_type_name

  properties {
    description = "UR3 Robot Thing Type"
  }
}

# IoT Thing
resource "aws_iot_thing" "ur3_robot_thing" {
  name            = var.thing_name
  thing_type_name = aws_iot_thing_type.ur3_robot_thing_type.name
}

# IoT Policy
resource "aws_iot_policy" "ur3_robot_policy" {
  name = "UR3RobotPolicy-${var.random_suffix}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iot:Connect",
          "iot:Publish",
          "iot:Subscribe",
          "iot:Receive"
        ]
        Resource = ["*"]
      }
    ]
  })
}

# IoT Certificate létrehozása és mentése
resource "aws_iot_certificate" "ur3_robot_cert" {
  active = true
}

# A policy csatolása a tanúsítványhoz
resource "aws_iot_policy_attachment" "ur3_robot_cert_attach_policy" {
  policy = aws_iot_policy.ur3_robot_policy.name
  target = aws_iot_certificate.ur3_robot_cert.arn
}

# A tanúsítvány (principal) csatolása a Thing-hez
resource "aws_iot_thing_principal_attachment" "ur3_robot_cert_attach_thing" {
  principal = aws_iot_certificate.ur3_robot_cert.arn
  thing     = aws_iot_thing.ur3_robot_thing.name
}

# A tanúsítvány és a kulcsok mentése a helyi 'certs' mappába
resource "local_file" "device_cert" {
  content  = aws_iot_certificate.ur3_robot_cert.certificate_pem
  filename = "${var.certs_output_path}/device.pem.crt"
}

resource "local_file" "device_private_key" {
  sensitive_content = aws_iot_certificate.ur3_robot_cert.private_key
  filename          = "${var.certs_output_path}/private.pem.key"
}

resource "local_file" "device_public_key" {
  content  = aws_iot_certificate.ur3_robot_cert.public_key
  filename = "${var.certs_output_path}/public.pem.key"
}

# IoT Rules
resource "aws_iot_topic_rule" "ur3_data_rule" {
  name        = "UR3DataProcessingRule${replace(var.random_suffix, "-", "")}"
  description = "Process UR3 Robot telemetry data"
  enabled     = true
  sql         = "SELECT * FROM '${var.telemetry_topic}'"
  sql_version = "2016-03-23"

  lambda {
    function_arn = aws_lambda_function.ur3_data_processor.arn
  }
}

resource "aws_iot_topic_rule" "ur3_command_rule" {
  name        = "UR3CommandRule${replace(var.random_suffix, "-", "")}"
  description = "Handle UR3 Robot commands from TwinMaker"
  enabled     = true
  sql         = "SELECT * FROM '${var.commands_topic}'"
  sql_version = "2016-03-23"

  lambda {
    function_arn = aws_lambda_function.ur3_data_processor.arn
  }
}