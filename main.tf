terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.7"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

data "aws_iot_endpoint" "current" {}



# Random string for resource naming
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}





# Lambda execution role
resource "aws_iam_role" "lambda_execution_role" {
  name = "UR3LambdaExecutionRole-${random_string.bucket_suffix.result}"

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

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.lambda_execution_role.name
}

resource "aws_iam_role_policy" "lambda_iot_and_messaging_policy"{
  name = "LambdaIoTAndMessagingPolicy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iottwinmaker:*"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iot:Publish",
          "iot:Subscribe",
          "iot:Connect",
          "iot:Receive"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM policy for WebSocket API access (for real-time data) 
resource "aws_iam_role_policy" "lambda_websocket_policy" {
  name = "LambdaRealtimeDataPolicy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid      = "AllowWebSocketPublish",
        Effect   = "Allow",
        Action   = "execute-api:ManageConnections",
        Resource = "arn:aws:execute-api:${var.aws_region}:${data.aws_caller_identity.current.account_id}:${module.websocket_api.websocket_api_id}/*"
      }
    ]
  })
}

# Policy for S3 read access (for the /logs API endpoint)
resource "aws_iam_role_policy" "lambda_s3_read_policy" {
  name = "LambdaAPIS3ReadPolicy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          module.s3_robot_data.bucket_arn,
          "${module.s3_robot_data.bucket_arn}/*"
        ]
      }
    ]
  })
}

# Policy for SQS send access (for the /command API endpoint)
resource "aws_iam_role_policy" "lambda_sqs_send_policy" {
  name = "LambdaAPISQSSendPolicy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "sqs:SendMessage"
        Resource = module.cloud_to_device_queue.queue_arn
      }
    ]
  })
}

# Policy for DynamoDB access for WebSocket connection management
resource "aws_iam_role_policy" "lambda_dynamodb_ws_policy" {
  name = "LambdaDynamoDBWebSocketPolicy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["dynamodb:PutItem", "dynamodb:DeleteItem", "dynamodb:Scan"],
        Resource = aws_dynamodb_table.websocket_connections.arn
      }
    ]
  })
}

# Lambda ZIP fájl
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "lambda-dist/iot-core_to_ws.zip"
  source {
    content = file("${path.module}/lambda/iot-core/lambda_data_connector.py")
    filename = "iotcore-ws.py"
  }
}

# Lambda Function
resource "aws_lambda_function" "ur3_data_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "ur3-data-processor"
  role             = aws_iam_role.lambda_execution_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.9"
  timeout          = 30
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      
      WEBSOCKET_API_ENDPOINT = replace(module.websocket_api.websocket_api_invoke_url, "wss://", "https://")
      DYNAMODB_TABLE_NAME    = aws_dynamodb_table.websocket_connections.name
    }
  }

  # removed depends_on = [data.archive_file.lambda_zip] because filename now references the data.source
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
  statement_id  = "AllowExecutionFromTwinMaker"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ur3_data_processor.function_name
  principal     = "iottwinmaker.amazonaws.com"
  source_account = data.aws_caller_identity.current.account_id
}

# IoT Thing Type
resource "aws_iot_thing_type" "ur3_robot_thing_type" {
  name = "UR3RobotType"
  
  properties {
    description = "UR3 Robot Thing Type"
  }
}

# IoT Thing
resource "aws_iot_thing" "ur3_robot_thing" {
  name           = "UR3-Robot-001"
  thing_type_name = aws_iot_thing_type.ur3_robot_thing_type.name
}

# IoT Policy
resource "aws_iot_policy" "ur3_robot_policy" {
  name = "UR3RobotPolicy-${random_string.bucket_suffix.result}"

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
  filename = "${path.module}/certs/device.pem.crt"
}

resource "local_file" "device_private_key" {
  # A privát kulcs érzékeny adat, így nem jelenik meg a plan/apply kimenetben
  sensitive_content = aws_iot_certificate.ur3_robot_cert.private_key
  filename          = "${path.module}/certs/private.pem.key"
}

resource "local_file" "device_public_key" {
  content  = aws_iot_certificate.ur3_robot_cert.public_key
  filename = "${path.module}/certs/public.pem.key"
}

# IoT Rules
resource "aws_iot_topic_rule" "ur3_data_rule" {
  name        = "UR3DataProcessingRule${replace(random_string.bucket_suffix.result, "-", "")}"
  description = "Process UR3 Robot telemetry data"
  enabled     = true
  sql         = "SELECT * FROM 'ur3/robot/telemetry'"
  sql_version = "2016-03-23"

  lambda {
    function_arn = aws_lambda_function.ur3_data_processor.arn
  }
}

resource "aws_iot_topic_rule" "ur3_command_rule" {
  name        = "UR3CommandRule${replace(random_string.bucket_suffix.result, "-", "")}"
  description = "Handle UR3 Robot commands from TwinMaker"
  enabled     = true
  sql         = "SELECT * FROM 'ur3/robot/commands'"
  sql_version = "2016-03-23"

  lambda {
    function_arn = aws_lambda_function.ur3_data_processor.arn
  }
}



########################################################################################################################
#                                     SQS-terraform conf                                                               #
########################################################################################################################


#INCOMING: Fizikai eszköz → Cloud (adatok fogadása)
module "device_to_cloud_queue" {
  source = "./modules/sqs"

  queue_name                    = "${var.project_name}-device-to-cloud"
  visibility_timeout_seconds    = 300
  message_retention_seconds     = 1209600  // 14 nap
  max_message_size              = 262144   // 256 KB
  delay_seconds                 = 0
  receive_wait_time_seconds     = 10       // Long polling
  
  enable_dlq                    = true
  max_receive_count             = 3
  
  tags = {
    Project     = var.common_tags["Project"]
    Environment = var.common_tags["Environment"]
    ManagedBy   = var.common_tags["ManagedBy"]
    Direction   = "Inbound"
    Purpose     = "Device telemetry and status"
  }
}

// OUTGOING: Cloud → Fizikai eszköz (parancsok visszaküldése)
module "cloud_to_device_queue" {
  source = "./modules/sqs"

  queue_name                    = "${var.project_name}-cloud-to-device"
  visibility_timeout_seconds    = 300
  message_retention_seconds     = 604800   // 7 nap (parancsok gyorsabban elévülnek)
  max_message_size              = 262144
  delay_seconds                 = 0
  receive_wait_time_seconds     = 10
  
  enable_dlq                    = true
  max_receive_count             = 5        
  tags = {
    Project     = var.common_tags["Project"]
    Environment = var.common_tags["Environment"]
    ManagedBy   = var.common_tags["ManagedBy"]
    Direction   = "Outbound"
    Purpose     = "Commands and control signals"
  }
}

module "s3_robot_data" {
  source = "./modules/s3-sqs-data"

  # Automatikusan generált egyedi bucket név
  bucket_name          = "robot-data-storage-${data.aws_caller_identity.current.account_id}"
  versioning_enabled   = var.s3_versioning_enabled
  encryption_algorithm = var.s3_encryption_algorithm

  lifecycle_rules = [
    {
      id              = "archive-old-data"
      status          = "Enabled"
      prefix          = "robot-data/"
      expiration_days = null
      transitions = [
        {
          days          = 30
          storage_class = "STANDARD_IA"
        },
        {
          days          = 90
          storage_class = "GLACIER"
        }
      ]
    }
  ]

  tags = var.common_tags
}
 

# Lambda modul
module "lambda_robot_processor" {
  source = "./modules/lambda-sqs"

  function_name    = var.lambda_function_name
  lambda_zip_path  = var.lambda_zip_path
  handler          = var.lambda_handler
  runtime          = var.lambda_runtime
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size
  
  # SQS trigger beállítása - KÖZVETLENÜL A MODULBÓL
  sqs_queue_arn       = module.device_to_cloud_queue.queue_arn
  sqs_batch_size      = var.lambda_sqs_batch_size
  sqs_trigger_enabled = var.lambda_sqs_trigger_enabled
  maximum_concurrency = var.lambda_max_concurrency

  # S3 konfiguráció - KÖZVETLENÜL A MODULBÓL
  s3_bucket_name = module.s3_robot_data.bucket_name
  s3_bucket_arn  = module.s3_robot_data.bucket_arn

  environment_variables = var.lambda_environment_variables
  log_retention_days    = var.lambda_log_retention_days

  tags = var.common_tags
}



// IAM role a fizikai eszköz számára (IoT Core vagy direkt SQS access)
resource "aws_iam_role" "device_role" {
  name = "${var.project_name}-device-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "iot.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "device_policy" {
  name = "${var.project_name}-device-policy"
  role = aws_iam_role.device_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl"
        ]
        Resource = module.device_to_cloud_queue.queue_arn
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = module.cloud_to_device_queue.queue_arn
      }
    ]
  })
}

// IAM role a cloud-oldali feldolgozó számára (Lambda/EC2)
resource "aws_iam_role" "cloud_processor_role" {
  name = "${var.project_name}-cloud-processor-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = ["lambda.amazonaws.com", "ec2.amazonaws.com"]
      }
    }]
  })
}

resource "aws_iam_role_policy" "cloud_processor_policy" {
  name = "${var.project_name}-cloud-processor-policy"
  role = aws_iam_role.cloud_processor_role.id

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
        Resource = module.device_to_cloud_queue.queue_arn
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = module.cloud_to_device_queue.queue_arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

// CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "incoming_queue_depth" {
  alarm_name          = "${var.project_name}-incoming-queue-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = "300"
  statistic           = "Average"
  threshold           = "1000"
  alarm_description   = "Alert when too many unprocessed device messages"
  
  dimensions = {
    QueueName = module.device_to_cloud_queue.queue_name
  }
}

resource "aws_cloudwatch_metric_alarm" "outgoing_queue_age" {
  alarm_name          = "${var.project_name}-outgoing-message-age"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = "300"
  statistic           = "Maximum"
  threshold           = "600"  
  alarm_description   = "Alert when commands are not picked up by device"
  
  dimensions = {
    QueueName = module.cloud_to_device_queue.queue_name
  }
}

// SNS Topic riasztásokhoz (opcionális)
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}

resource "aws_sns_topic_subscription" "alert_email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Lambda ZIP fájlok
data "archive_file" "s3_read_lambda" {
  type        = "zip"
  output_path = "${path.module}/lambda-dist/s3-read-logs.zip"
  source {
    content  = file("${path.module}/lambda/api/read_logs.py")
    filename = "index.py"
  }
}

data "archive_file" "command_lambda" {
  type        = "zip"
  output_path = "${path.module}/lambda-dist/send-command.zip"
  source {
    content  = file("${path.module}/lambda/api/send_command.py")
    filename = "index.py"
  }
}

# Lambda függvény az S3 logok olvasásához
resource "aws_lambda_function" "s3_read_logs" {
  filename         = data.archive_file.s3_read_lambda.output_path
  function_name    = "${var.project_name}-read-logs"
  role             = aws_iam_role.lambda_execution_role.arn # <-- EGYSÉGESÍTETT SZEREPKÖR HASZNÁLATA
  handler         = "index.lambda_handler"
  runtime         = "python3.11"
  timeout         = 30
  memory_size     = 512
  source_code_hash = data.archive_file.s3_read_lambda.output_base64sha256

  environment {
    variables = {
      S3_BUCKET_NAME = module.s3_robot_data.bucket_name
    }
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_log_group" "s3_read_logs_lambda" {
  name              = "/aws/lambda/${aws_lambda_function.s3_read_logs.function_name}"
  retention_in_days = 7

  tags = var.common_tags
}

# Lambda függvény parancsok küldéséhez
resource "aws_lambda_function" "send_command" {
  filename         = data.archive_file.command_lambda.output_path
  function_name    = "${var.project_name}-send-command"
  role             = aws_iam_role.lambda_execution_role.arn # <-- EGYSÉGESÍTETT SZEREPKÖR HASZNÁLATA
  handler         = "index.lambda_handler"
  runtime         = "python3.11"
  timeout         = 30
  source_code_hash = data.archive_file.command_lambda.output_base64sha256

  environment {
    variables = {
      COMMAND_QUEUE_URL = module.cloud_to_device_queue.queue_url
    }
  }

  tags = var.common_tags
}

resource "aws_cloudwatch_log_group" "send_command_lambda" {
  name              = "/aws/lambda/${aws_lambda_function.send_command.function_name}"
  retention_in_days = 7

  tags = var.common_tags
}

# ######################################################################################################################
# #                                     WebSocket API and Handlers                                                       #
# ######################################################################################################################

# DynamoDB table to store WebSocket connection IDs
resource "aws_dynamodb_table" "websocket_connections" {
  name           = var.websocket_dynamodb_table
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "connectionId"

  attribute {
    name = "connectionId"
    type = "S"
  }

  tags = var.common_tags
}

# ZIP file for the connect handler
data "archive_file" "ws_connect_lambda" {
  type        = "zip"
  output_path = "${path.module}/lambda-dist/ws-connect.zip"
  source {
    content  = file("${path.module}/lambda/ws/connect.py")
    filename = "index.py"
  }
}

# ZIP file for the disconnect handler
data "archive_file" "ws_disconnect_lambda" {
  type        = "zip"
  output_path = "${path.module}/lambda-dist/ws-disconnect.zip"
  source {
    content  = file("${path.module}/lambda/ws/disconnect.py")
    filename = "index.py"
  }
}

# ZIP file for the default handler
data "archive_file" "ws_default_lambda" {
  type        = "zip"
  output_path = "${path.module}/lambda-dist/ws-default.zip"
  source {
    content  = file("${path.module}/lambda/ws/default.py")
    filename = "index.py"
  }
}

# Lambda function for WebSocket $connect
resource "aws_lambda_function" "ws_connect" {
  filename         = data.archive_file.ws_connect_lambda.output_path
  function_name    = "${var.project_name}-ws-connect"
  role             = aws_iam_role.lambda_execution_role.arn
  handler          = "index.handler"
  runtime          = "python3.11"
  source_code_hash = data.archive_file.ws_connect_lambda.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.websocket_connections.name
    }
  }
  tags = var.common_tags
}

# Lambda function for WebSocket $disconnect
resource "aws_lambda_function" "ws_disconnect" {
  filename         = data.archive_file.ws_disconnect_lambda.output_path
  function_name    = "${var.project_name}-ws-disconnect"
  role             = aws_iam_role.lambda_execution_role.arn
  handler          = "index.handler"
  runtime          = "python3.11"
  source_code_hash = data.archive_file.ws_disconnect_lambda.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.websocket_connections.name
    }
  }
  tags = var.common_tags
}

# Lambda function for WebSocket $default
resource "aws_lambda_function" "ws_default" {
  filename         = data.archive_file.ws_default_lambda.output_path
  function_name    = "${var.project_name}-ws-default"
  role             = aws_iam_role.lambda_execution_role.arn
  handler          = "index.handler"
  runtime          = "python3.11"
  source_code_hash = data.archive_file.ws_default_lambda.output_base64sha256

  tags = var.common_tags
}

# WebSocket API Gateway
module "websocket_api" {
  source = "./modules/api-gateway-websocket"

  api_name = "${var.project_name}-realtime-api"
  aws_region = var.aws_region

  connect_lambda_invoke_arn    = aws_lambda_function.ws_connect.invoke_arn
  connect_lambda_function_name = aws_lambda_function.ws_connect.function_name
  disconnect_lambda_invoke_arn = aws_lambda_function.ws_disconnect.invoke_arn
  disconnect_lambda_function_name = aws_lambda_function.ws_disconnect.function_name
  default_lambda_invoke_arn    = aws_lambda_function.ws_default.invoke_arn
  default_lambda_function_name = aws_lambda_function.ws_default.function_name

  depends_on = [
    aws_lambda_function.ws_connect,
    aws_lambda_function.ws_disconnect,
    aws_lambda_function.ws_default
  ]

  tags = var.common_tags
}

# DynamoDB table to store the twin's operational mode (CONNECTED vs SIMULATED)
resource "aws_dynamodb_table" "twin_state" {
  name           = "${var.project_name}-twin-state"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "entityId"

  attribute {
    name = "entityId"
    type = "S"
  }

  tags = var.common_tags
}


# ######################################################################################################################
# #                                     UR RTDE Controller Lambda with Layer                                             #
# ######################################################################################################################

# Lambda Layer for ur-rtde library
resource "aws_lambda_layer_version" "ur_rtde_layer" {
  filename            = var.ur_rtde_layer_zip_path
  layer_name          = "ur-rtde-library"
  compatible_runtimes = ["python3.10"]
  description         = "Lambda Layer containing the ur-rtde Python library"
}

# ZIP file for the UR controller Lambda
data "archive_file" "ur_controller_lambda" {
  type        = "zip"
  output_path = "${path.module}/lambda-dist/ur-controller.zip"
  source {
    content  = file(var.ur_controller_lambda_source_path)
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

# Example policy: Allow sending commands to the SQS queue
# You might need to add other permissions, e.g., for VPC access if you need direct network communication
resource "aws_iam_role_policy" "ur_controller_lambda_policy" {
  name = "${var.project_name}-ur-controller-sqs-policy"
  role = aws_iam_role.ur_controller_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl"
        ]
        Resource = module.cloud_to_device_queue.queue_arn
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
  timeout          = 60 # Increased timeout might be needed for robot communication
  source_code_hash = data.archive_file.ur_controller_lambda.output_base64sha256

  layers = [aws_lambda_layer_version.ur_rtde_layer.arn]

  environment {
    variables = {
      COMMAND_QUEUE_URL = module.cloud_to_device_queue.queue_url
      # Add other necessary environment variables here
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

######################################################################################################################
#                                     API Gateway (REST API)                                                         #
######################################################################################################################

# --- API Gateway REST API ---
module "ur3_api_gateway" {
  source = "./modules/api-gateway-rest"

  api_name             = "${var.project_name}-api"
  api_description      = "REST API for UR3 Digital Twin"
  stage_name           = "prod" # Vagy var.api_stage_name, ha változóként akarod kezelni

  # Logs endpoint konfiguráció
  lambda_invoke_arn    = aws_lambda_function.s3_read_logs.invoke_arn
  lambda_function_name = aws_lambda_function.s3_read_logs.function_name

  # Command endpoint konfiguráció (a /command és /command/quick végpontokhoz is)
  command_lambda_invoke_arn    = aws_lambda_function.send_command.invoke_arn
  command_lambda_function_name = aws_lambda_function.send_command.function_name

  tags = var.common_tags
}

# Amplify IAM role
resource "aws_iam_role" "amplify_role" {
  name = "${var.project_name}-amplify-role"

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

  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "amplify_backend" {
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess-Amplify"
  role       = aws_iam_role.amplify_role.name
}

# GitHub connection (optional: only if github_personal_access_token is provided)
resource "aws_amplify_app" "github_connected" {
  name       = "${var.project_name}-logs-dashboard"
  repository = "https://github.com/${var.github_repo_owner}/${var.github_repo_name}"
  access_token = var.github_personal_access_token
  platform = "WEB"
  
  build_spec = <<-EOT
    version: 1
    frontend:
      phases:
        preBuild:
          commands:
            - npm install --prefix frontend
        build:
          commands:
            - npm run build --prefix frontend
      artifacts:
        baseDirectory: frontend/build
        files:
          - '**/*'
      cache:
        paths:
          - frontend/node_modules/**/*
  EOT

  custom_rule {
    source = "^[^.]+$|\\.(?!(css|gif|ico|jpg|js|png|txt|svg|woff|woff2|ttf|map|json)$)([^.]+$)"
    status = "200"
    target = "/index.html"
  }

  iam_service_role_arn = aws_iam_role.amplify_role.arn

  tags = var.common_tags
}

# GitHub branch (if GitHub token provided)
resource "aws_amplify_branch" "github_main" {
  app_id      = aws_amplify_app.github_connected.id
  branch_name = var.amplify_branch_name

  environment_variables = {
    REACT_APP_API_URL         = module.ur3_api_gateway.api_url
    REACT_APP_COMMAND_API_URL = module.ur3_api_gateway.command_api_url
    REACT_APP_COMMAND_QUICK_API_URL = module.ur3_api_gateway.command_quick_api_url # Új környezeti változó
    REACT_APP_WEBSOCKET_URL   = module.websocket_api.websocket_api_invoke_url
  }

  enable_auto_build = true
  framework         = "React"
  stage             = "PRODUCTION"
}



output "iot_endpoint" {
  description = "The endpoint for the AWS IoT Core service. Copy this to your core-test.py and ur-rtde.py scripts."
  value       = data.aws_iot_endpoint.current.endpoint_address
}