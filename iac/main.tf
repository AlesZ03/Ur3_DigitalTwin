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

resource "aws_iam_role_policy" "lambda_iot_and_messaging_policy" {
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

# Policy for DynamoDB read access (for the /logs API endpoint)
resource "aws_iam_role_policy" "lambda_dynamodb_read_policy" {
  name = "LambdaAPIDynamoDBReadPolicy"
  role = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:Query",
          "dynamodb:Scan"
        ]

        Resource = "arn:aws:dynamodb:*:*:table/*telemetry*"
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
          "${module.s3_robot_data.bucket_arn}/*",
          module.firehose_ingestion.bucket_arn,
          "${module.firehose_ingestion.bucket_arn}/*"
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
#                                      Remote Backend                                                                  #
########################################################################################################################
terraform {
  backend "s3" {

    use_lockfile = true

  }
}



########################################################################################################################
#                                     IOT-Core conf                                                                    #
########################################################################################################################
module "iot_core" {
  source = "./modules/iot-core"

  project_name      = var.project_name
  aws_region        = var.aws_region
  account_id        = data.aws_caller_identity.current.account_id
  thing_name        = "UR3-Robot-001"
  certs_output_path = "${path.module}/../edge_device/certs"
  tags              = var.common_tags

  appsync_api_url = module.appsync_api.api_url
  appsync_api_id  = module.appsync_api.api_id
  iot_endpoint    = data.aws_iot_endpoint.current.endpoint_address

}
########################################################################################################################
#                                     DynamoDB conf                                                                    #
########################################################################################################################


module "dynamodb_storage" {
  source             = "./modules/dynamodb"
  project_name       = var.project_name
  lambda_source_path = "lambda/dynamodb/writer.py"
  tags               = var.common_tags
}
########################################################################################################################
#                                     Firehose conf                                                                    #
########################################################################################################################



module "firehose_ingestion" {
  source            = "./modules/firehose"
  project_name      = var.project_name
  account_id        = data.aws_caller_identity.current.account_id
  aws_region        = var.aws_region
  lambda_writer_arn = module.dynamodb_storage.writer_lambda_arn
  tags              = var.common_tags


}
########################################################################################################################
#                                     SQS-terraform conf                                                               #
########################################################################################################################


#INCOMING: Fizikai eszköz → Cloud (adatok fogadása)
module "device_to_cloud_queue" {
  source = "./modules/sqs"

  queue_name                 = "${var.project_name}-device-to-cloud"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 1209600 // 14 nap
  max_message_size           = 262144  // 256 KB
  delay_seconds              = 0
  receive_wait_time_seconds  = 10 // Long polling

  enable_dlq        = true
  max_receive_count = 3

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

  queue_name                 = "${var.project_name}-cloud-to-device"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 604800 // 7 nap (parancsok gyorsabban elévülnek)
  max_message_size           = 262144
  delay_seconds              = 0
  receive_wait_time_seconds  = 10

  enable_dlq        = true
  max_receive_count = 5
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

  function_name           = var.lambda_function_name
  lambda_source_file_path = "${path.module}/lambda/sqs/data-sqs.py"
  lambda_output_zip_path  = "${path.module}/lambda-dist/${var.lambda_function_name}.zip"
  handler                 = var.lambda_handler
  runtime                 = var.lambda_runtime
  timeout                 = var.lambda_timeout
  memory_size             = var.lambda_memory_size

  # SQS trigger beállítása 
  sqs_queue_arn       = module.device_to_cloud_queue.queue_arn
  sqs_batch_size      = var.lambda_sqs_batch_size
  sqs_trigger_enabled = var.lambda_sqs_trigger_enabled
  maximum_concurrency = var.lambda_max_concurrency

  # S3 konfiguráció 
  s3_bucket_name = module.s3_robot_data.bucket_name
  s3_bucket_arn  = module.s3_robot_data.bucket_arn

  environment_variables = var.lambda_environment_variables
  log_retention_days    = var.lambda_log_retention_days

  tags = var.common_tags
}
module "backend_monitoring" {
  source = "./modules/monitoring"

  project_name = var.project_name
  alert_email  = var.alert_email

  device_to_cloud_queue_arn = module.device_to_cloud_queue.queue_arn
  cloud_to_device_queue_arn = module.cloud_to_device_queue.queue_arn


  device_to_cloud_queue_name = module.device_to_cloud_queue.queue_name
  cloud_to_device_queue_name = module.cloud_to_device_queue.queue_name
}
######################################################################################################################
#                                     SQS to IoT Core Bridge Lambda                                                  #
######################################################################################################################

module "lambda_iot_bridge" {
  source = "./modules/lambda-bridge-sqs-iot"

  bridge_function_name = "${var.project_name}-sqs-to-iot"


  sqs_queue_arn = module.cloud_to_device_queue.queue_arn

  iot_endpoint = data.aws_iot_endpoint.current.endpoint_address
  iot_topic    = "ur3/commands"


  bridge_lambda_source_file_path = "${path.module}/lambda/sqs/iot-core-sqs.py"
  bridge_lambda_output_zip_path  = "${path.module}/lambda-dist/bridge.zip"
}
######################################################################################################################
#                                     AppSync for Real-time Data (Modular)                                           #
######################################################################################################################

module "appsync_api" {
  source = "./modules/app-sync"

  project_name          = var.project_name
  aws_region            = var.aws_region
  account_id            = data.aws_caller_identity.current.account_id
  schema_path           = "${path.module}/modules/app-sync/schema.graphql"
  tags                  = var.common_tags
  iot_bridge_lambda_arn = module.iot_core.lambda_arn

}


# ######################################################################################################################
# #                                     UR RTDE Controller Lambda with Layer                                             #
# ######################################################################################################################

module "lambda_backend" {
  source = "./modules/lambda-backend"

  project_name                     = var.project_name
  common_tags                      = var.common_tags
  ur_rtde_layer_zip_path           = var.ur_rtde_layer_zip_path
  ur_controller_lambda_source_path = var.ur_controller_lambda_source_path

  cloud_to_device_queue_arn = module.cloud_to_device_queue.queue_arn
  cloud_to_device_queue_url = module.cloud_to_device_queue.queue_url
}

######################################################################################################################
#                                     API Gateway (REST API)                                                         #
######################################################################################################################

# --- API Gateway REST API ---
module "ur3_api_gateway" {
  source = "./modules/api-gateway-rest"

  api_name        = "${var.project_name}-api"
  api_description = "REST API for UR3 Digital Twin"
  stage_name      = "prod"
  project_name    = var.project_name

  lambda_execution_role_arn = aws_iam_role.lambda_execution_role.arn
  s3_bucket_name            = module.s3_robot_data.bucket_name
  command_queue_url         = module.cloud_to_device_queue.queue_url
  telemetry_table_name      = module.dynamodb_storage.dynamodb_table_name
  tags                      = var.common_tags
  firehose_s3_bucket_name   = module.firehose_ingestion.bucket_name
}
######################################################################################################################
#                                     Amplify configuration                                                          #
######################################################################################################################
module "amplify_frontend" {
  source = "./modules/amplify"

  app_name       = "${var.project_name}-logs-dashboard"
  repository_url = "https://github.com/${var.github_repo_owner}/${var.github_repo_name}"
  access_token   = var.github_personal_access_token
  branch_name    = var.amplify_branch_name

  enable_branch_auto_build = true
  framework                = "React"
  stage                    = "PRODUCTION"

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

  custom_rules = [
    {
      source = "^[^.]+$|\\.(?!(css|gif|ico|jpg|js|png|txt|svg|woff|woff2|ttf|map|json)$)([^.]+$)"
      status = "200"
      target = "/index.html"
    }
  ]


  branch_environment_variables = {
    REACT_APP_API_URL               = module.ur3_api_gateway.api_url
    REACT_APP_COMMAND_API_URL       = module.ur3_api_gateway.command_api_url
    REACT_APP_COMMAND_QUICK_API_URL = module.ur3_api_gateway.command_quick_api_url
    REACT_APP_APPSYNC_URL           = module.appsync_api.api_url
    REACT_APP_APPSYNC_API_KEY       = module.appsync_api.api_key
    REACT_APP_APPSYNC_REGION        = var.aws_region
  }

  tags = var.common_tags
}