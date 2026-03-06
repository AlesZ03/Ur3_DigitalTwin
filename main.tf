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

########################################################################################################################
#                                     IOT-Core conf                                                                    #
########################################################################################################################
module "iot_core" {
  source = "./modules/iot-core"

  project_name    = var.project_name
  aws_region      = var.aws_region
  account_id      = data.aws_caller_identity.current.account_id
  thing_name      = "UR3-Robot-001" # Must match CLIENT_ID in ur-rtde.py
  certs_output_path = "${path.module}/certs"
  tags            = var.common_tags

  appsync_api_url = module.appsync_api.api_url
  appsync_api_id  = module.appsync_api.api_id
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
  lambda_source_file_path = "${path.module}/lambda/sqs/data-sqs.py"
  lambda_output_zip_path  = "${path.module}/lambda-dist/${var.lambda_function_name}.zip"
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

######################################################################################################################
#                                     AppSync for Real-time Data (Modular)                                           #
######################################################################################################################

module "appsync_api" { # Renamed from "app_sync" to match the module call
  source = "./modules/app-sync"

  project_name = var.project_name
  aws_region   = var.aws_region
  account_id   = data.aws_caller_identity.current.account_id
  schema_path  = "${path.module}/schema.graphql"
  tags         = var.common_tags
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
######################################################################################################################
#                                     Amplify configuration                                                          #
######################################################################################################################

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
    REACT_APP_API_URL               = module.ur3_api_gateway.api_url
    REACT_APP_COMMAND_API_URL       = module.ur3_api_gateway.command_api_url
    REACT_APP_COMMAND_QUICK_API_URL = module.ur3_api_gateway.command_quick_api_url # Új környezeti változó
    REACT_APP_APPSYNC_URL           = module.appsync_api.api_url
    REACT_APP_APPSYNC_API_KEY       = module.appsync_api.api_key
    REACT_APP_APPSYNC_REGION        = var.aws_region
  }

  enable_auto_build = true
  framework         = "React"
  stage             = "PRODUCTION"
}