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
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

# Local values - a tetején definiálva
locals {
  workspace_id = "ur3-workspace-terraform"
  entity_id    = "ur3-robot-001"
  scene_id     = "ur3-robot-scene"
}

# Random string for resource naming
resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

# S3 bucket a GLB fájlhoz és scene adatokhoz
resource "aws_s3_bucket" "ur3_scene_bucket" {
  bucket        = "ur3-twin-scene-${random_string.bucket_suffix.result}"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "ur3_scene_bucket_versioning" {
  bucket = aws_s3_bucket.ur3_scene_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# CORS beállítás a bucket-hez
resource "aws_s3_bucket_cors_configuration" "ur3_scene_bucket_cors" {
  bucket = aws_s3_bucket.ur3_scene_bucket.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_public_access_block" "ur3_scene_bucket_pab" {
  bucket = aws_s3_bucket.ur3_scene_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# Javított S3 bucket policy
resource "aws_s3_bucket_policy" "ur3_scene_bucket_policy" {
  bucket = aws_s3_bucket.ur3_scene_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "iottwinmaker.amazonaws.com"
        }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketVersioning"
        ]
        Resource = [
          aws_s3_bucket.ur3_scene_bucket.arn,
          "${aws_s3_bucket.ur3_scene_bucket.arn}/*"
        ]
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.twinmaker_execution_role.arn
        }
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketVersioning"
        ]
        Resource = [
          aws_s3_bucket.ur3_scene_bucket.arn,
          "${aws_s3_bucket.ur3_scene_bucket.arn}/*"
        ]
      }
    ]
  })

  depends_on = [aws_iam_role.twinmaker_execution_role]
}

# GLB fájl feltöltése (opcionális, ha van GLB fájlod)
resource "aws_s3_object" "ur3_glb_file" {
  count  = fileexists(var.glb_file_path) ? 1 : 0
  bucket = aws_s3_bucket.ur3_scene_bucket.id
  key    = "models/ur3_robot.glb"
  source = var.glb_file_path
  etag   = filemd5(var.glb_file_path)
}

# TwinMaker execution role
resource "aws_iam_role" "twinmaker_execution_role" {
  name = "TwinMakerExecutionRole-${random_string.bucket_suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "iottwinmaker.amazonaws.com"
        }
      }
    ]
  })
}

# TwinMaker S3 policy
resource "aws_iam_role_policy" "twinmaker_s3_policy" {
  name = "TwinMakerS3Policy"
  role = aws_iam_role.twinmaker_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:GetBucketVersioning",
          "s3:GetBucketPolicy"
        ]
        Resource = [
          aws_s3_bucket.ur3_scene_bucket.arn,
          "${aws_s3_bucket.ur3_scene_bucket.arn}/*"
        ]
      }
    ]
  })
}

# TwinMaker additional services policy
resource "aws_iam_role_policy" "twinmaker_additional_policy" {
  name = "TwinMakerAdditionalPolicy"
  role = aws_iam_role.twinmaker_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iottwinmaker:*",
          "iot:DescribeThing",
          "iot:ListThings",
          "iotsitewise:*",
          "kinesisvideo:*",
          "timestream:*",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.twinmaker_execution_role.arn
      }
    ]
  })
}

# TwinMaker Lambda integration policy
resource "aws_iam_role_policy" "twinmaker_lambda_policy" {
  name = "TwinMakerLambdaPolicy"
  role = aws_iam_role.twinmaker_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction",
          "lambda:GetFunction",
          "lambda:ListFunctions"
        ]
        Resource = [
          aws_lambda_function.ur3_data_processor.arn,
          "${aws_lambda_function.ur3_data_processor.arn}:*"
        ]
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

resource "aws_iam_role_policy" "lambda_twinmaker_policy" {
  name = "LambdaTwinMakerPolicy"
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

# Lambda ZIP fájl
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "ur3_lambda.zip"
  source {
    content = file("${path.module}/lambda_data_connector.py")
    filename = "lambda_function.py"
  }
}

# Lambda Function
resource "aws_lambda_function" "ur3_data_processor" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "ur3-data-processor-${random_string.bucket_suffix.result}"
  role             = aws_iam_role.lambda_execution_role.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.9"
  timeout          = 30

  environment {
    variables = {
      WORKSPACE_ID = local.workspace_id
      ENTITY_ID    = local.entity_id
      S3_BUCKET    = aws_s3_bucket.ur3_scene_bucket.bucket
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

# Várakozás az IAM szerepkör propagálásához
resource "time_sleep" "wait_for_iam" {
  depends_on = [
    aws_iam_role_policy.twinmaker_s3_policy,
    aws_iam_role_policy.twinmaker_additional_policy,
    aws_iam_role_policy.twinmaker_lambda_policy,
    aws_s3_bucket_policy.ur3_scene_bucket_policy
  ]
  
  create_duration = "90s"
}

# TwinMaker Workspace és kapcsolódó erőforrások létrehozása
resource "null_resource" "twinmaker_setup" {
  depends_on = [
    aws_s3_bucket.ur3_scene_bucket,
    aws_s3_bucket_policy.ur3_scene_bucket_policy,
    aws_iam_role.twinmaker_execution_role,
    aws_lambda_function.ur3_data_processor,
    time_sleep.wait_for_iam,
    aws_s3_bucket_versioning.ur3_scene_bucket_versioning,
    aws_lambda_permission.allow_twinmaker
  ]

  triggers = {
    workspace_id = local.workspace_id
    entity_id    = local.entity_id
    scene_id     = local.scene_id
    iam_role_arn = aws_iam_role.twinmaker_execution_role.arn
    s3_bucket    = aws_s3_bucket.ur3_scene_bucket.bucket
    lambda_arn   = aws_lambda_function.ur3_data_processor.arn
    region       = var.aws_region
  }

  provisioner "local-exec" {
    command = <<-EOT
      python3 ${path.module}/twinmaker_setup.py \
        --region ${var.aws_region} \
        --workspace-id ${local.workspace_id} \
        --entity-id ${local.entity_id} \
        --scene-id ${local.scene_id} \
        --role-arn ${aws_iam_role.twinmaker_execution_role.arn} \
        --s3-bucket ${aws_s3_bucket.ur3_scene_bucket.bucket} \
        --lambda-arn ${aws_lambda_function.ur3_data_processor.arn}
    EOT
  }
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      python3 ${path.module}/twinmaker_setup.py \
        --region ${self.triggers.region} \
        --workspace-id ${self.triggers.workspace_id} \
        --entity-id ${self.triggers.entity_id} \
        --scene-id ${self.triggers.scene_id} \
        --role-arn ${self.triggers.iam_role_arn} \
        --s3-bucket ${self.triggers.s3_bucket} \
        --lambda-arn ${self.triggers.lambda_arn} \
        --cleanup
    EOT
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
  max_receive_count             = 5        // Több újrapróbálkozás parancsokhoz
  
  tags = {
    Project     = var.common_tags["Project"]
    Environment = var.common_tags["Environment"]
    ManagedBy   = var.common_tags["ManagedBy"]
    Direction   = "Outbound"
    Purpose     = "Commands and control signals"
  }
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
  threshold           = "600"  // 10 perc
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

# Debug outputs
output "debug_info" {
  value = {
    workspace_id = local.workspace_id
    entity_id    = local.entity_id
    scene_id     = local.scene_id
    iam_role_arn = aws_iam_role.twinmaker_execution_role.arn
    s3_bucket    = aws_s3_bucket.ur3_scene_bucket.bucket
    lambda_arn   = aws_lambda_function.ur3_data_processor.arn
    region       = var.aws_region
  }
}

# Hasznos URL-ek
output "twinmaker_workspace_url" {
  value = "https://${var.aws_region}.console.aws.amazon.com/iottwinmaker/home?region=${var.aws_region}#/workspaces/${local.workspace_id}"
}

output "twinmaker_workspace_direct_url" {
  value = "https://console.aws.amazon.com/iottwinmaker/home?region=${var.aws_region}#/workspaces/${local.workspace_id}/dashboard"
}

# output "iot_test_console_url" {
#   value = "https://console.aws.amazon.com/iot/home?region=${var.aws_region}#/test"
# }

# output "lambda_function_name" {
#   value = aws_lambda_function.ur3_data_processor.function_name
#}





