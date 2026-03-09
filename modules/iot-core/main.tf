terraform {
  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

# Create an IoT Thing to represent the robot.
resource "aws_iot_thing" "ur3_robot" {
  name = var.thing_name
}

# IoT Policy
resource "aws_iot_policy" "ur3_robot_policy" {
  name = "${var.project_name}-robot-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Allows connecting to IoT Core with a specific client ID
        Effect   = "Allow"
        Action   = "iot:Connect"
        Resource = "arn:aws:iot:${var.aws_region}:${var.account_id}:client/${aws_iot_thing.ur3_robot.name}"
      },
      {
        # Allows publishing to the device's own shadow topic
        Effect   = "Allow"
        Action   = "iot:Publish"
        Resource = "arn:aws:iot:${var.aws_region}:${var.account_id}:topic/$aws/things/${aws_iot_thing.ur3_robot.name}/shadow/update"
      },
      {
        # Allows receiving responses from the shadow service
        Effect   = "Allow"
        Action   = "iot:Receive"
        Resource = "*"
      },
      {
        # Allows subscribing to shadow response topics
        Effect   = "Allow"
        Action   = "iot:Subscribe"
        Resource = [
        "arn:aws:iot:us-east-1:359289023072:topicfilter/$aws/things/UR3-Robot-001/shadow/*",
        "arn:aws:iot:us-east-1:359289023072:topicfilter/ur3/commands"]
      }
    ]
  })
}

resource "aws_iot_certificate" "ur3_robot_cert" {
  active = true
}

resource "aws_iot_policy_attachment" "ur3_robot_cert_attach_policy" {
  policy = aws_iot_policy.ur3_robot_policy.name
  target = aws_iot_certificate.ur3_robot_cert.arn
}

resource "aws_iot_thing_principal_attachment" "ur3_robot_cert_attach_thing" {
  principal = aws_iot_certificate.ur3_robot_cert.arn
  thing     = aws_iot_thing.ur3_robot.name
}

# --- Save certificates locally for the Python script ---

# Download the Amazon Root CA1 certificate
data "http" "amazon_root_ca1" {
  url = "https://www.amazontrust.com/repository/AmazonRootCA1.pem"
}

resource "local_file" "device_cert" {
  content  = aws_iot_certificate.ur3_robot_cert.certificate_pem
  filename = "${var.certs_output_path}/device.pem.crt"
}

resource "local_sensitive_file" "private_key" {
  content  = aws_iot_certificate.ur3_robot_cert.private_key
  filename = "${var.certs_output_path}/private.pem.key"
}

resource "local_file" "root_ca" {
  content  = data.http.amazon_root_ca1.response_body
  filename = "${var.certs_output_path}/AmazonRootCA1.pem"
}

################################################################################
# Lambda híd az IoT Core és az AppSync között
################################################################################

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.root}/lambda/iot-core/lambda_data_connector.py"
  output_path = "${path.root}/lambda-dist/iot_to_appsync_forwarder.zip"
}

resource "aws_lambda_function" "iot_to_appsync_forwarder" {
  function_name = "${var.project_name}-iot-forwarder"
  handler       = "lambda_data_connector.lambda_handler"
  runtime       = "python3.9"
  role          = aws_iam_role.lambda_exec_role.arn

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
  variables = {
    APPSYNC_API_URL = var.appsync_api_url
    IOT_ENDPOINT    = var.iot_endpoint 
  }
}

  tags = var.tags
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.project_name}-iot-forwarder-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-iot-forwarder-lambda-policy"
  role = aws_iam_role.lambda_exec_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
 
      {
        Effect   = "Allow",
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
        Resource = "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:/aws/lambda/${aws_lambda_function.iot_to_appsync_forwarder.function_name}:*"
      },
 
      {
        Effect   = "Allow",
        Action   = [
          "appsync:GraphQL",
          "iot:GetThingShadow"  
        ],
   
        Resource = "*" 
      }
    ]
  })
}

resource "aws_iot_topic_rule" "forward_to_lambda" {
  name        = "${replace(var.project_name, "-", "_")}_forward_shadow_to_lambda"
  description = "Triggers a Lambda function on every accepted shadow update."
  enabled     = true
  sql         = "SELECT * FROM '$aws/things/${aws_iot_thing.ur3_robot.name}/shadow/update/accepted'"
  sql_version = "2016-03-23"

  lambda {
    function_arn = aws_lambda_function.iot_to_appsync_forwarder.arn
  }

  tags = var.tags
}

resource "aws_lambda_permission" "allow_iot" {
  statement_id  = "AllowExecutionFromIoT"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.iot_to_appsync_forwarder.function_name
  principal     = "iot.amazonaws.com"
  source_arn    = aws_iot_topic_rule.forward_to_lambda.arn
}