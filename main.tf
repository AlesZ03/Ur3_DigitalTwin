terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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
  bucket = "ur3-twin-scene-${random_string.bucket_suffix.result}"
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
  filename         = "ur3_lambda.zip"
  function_name    = "ur3-data-processor-${random_string.bucket_suffix.result}"
  role            = aws_iam_role.lambda_execution_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = 30

  environment {
    variables = {
      WORKSPACE_ID = local.workspace_id
      ENTITY_ID    = local.entity_id
      S3_BUCKET    = aws_s3_bucket.ur3_scene_bucket.bucket
    }
  }

  depends_on = [data.archive_file.lambda_zip]
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
resource "null_resource" "create_twinmaker_resources" {
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
    workspace_id   = local.workspace_id
    entity_id      = local.entity_id
    scene_id       = local.scene_id
    iam_role_arn   = aws_iam_role.twinmaker_execution_role.arn
    s3_bucket      = aws_s3_bucket.ur3_scene_bucket.bucket
    lambda_arn     = aws_lambda_function.ur3_data_processor.arn
    region         = var.aws_region
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      
      echo "=== TwinMaker Workspace Creation ==="
      echo "Workspace ID: ${local.workspace_id}"
      echo "IAM Role ARN: ${aws_iam_role.twinmaker_execution_role.arn}"
      echo "S3 Bucket: ${aws_s3_bucket.ur3_scene_bucket.bucket}"
      echo "Lambda ARN: ${aws_lambda_function.ur3_data_processor.arn}"
      echo "AWS Region: ${var.aws_region}"
      
      # AWS konfigurációjának ellenőrzése
      echo "Checking AWS configuration..."
      aws sts get-caller-identity
      
      # IAM szerepkör ellenőrzése
      echo "Checking IAM role..."
      aws iam get-role --role-name TwinMakerExecutionRole-${random_string.bucket_suffix.result}
      
      # S3 bucket ellenőrzése
      echo "Checking S3 bucket..."
      aws s3 ls s3://${aws_s3_bucket.ur3_scene_bucket.bucket}/
      
      # Workspace létrehozása vagy ellenőrzése
      echo "Checking if workspace exists..."
      if aws iottwinmaker get-workspace --workspace-id ${local.workspace_id} 2>/dev/null; then
        echo "Workspace already exists, checking state..."
      else
        echo "Creating TwinMaker workspace..."
        aws iottwinmaker create-workspace \
          --workspace-id ${local.workspace_id} \
          --description "UR3 Robot Digital Twin Workspace" \
          --role ${aws_iam_role.twinmaker_execution_role.arn} \
          --s3-location ${aws_s3_bucket.ur3_scene_bucket.arn} \
          --region ${var.aws_region}
      fi

      # Workspace állapotának várása
      echo "Waiting for workspace to become active..."
      TIMEOUT=1800  # 30 perc
      ELAPSED=0
      
      while [ $ELAPSED -lt $TIMEOUT ]; do
        WORKSPACE_STATE=$(aws iottwinmaker get-workspace --workspace-id ${local.workspace_id} --query 'state' --output text 2>/dev/null || echo "NONE")
        echo "Workspace state: $WORKSPACE_STATE (elapsed: $${ELAPSED}s)"
        
        if [ "$WORKSPACE_STATE" = "ACTIVE" ]; then
          echo "Workspace is now ACTIVE!"
          break
        elif [ "$WORKSPACE_STATE" = "ERROR" ]; then
          echo "Workspace entered ERROR state!"
          aws iottwinmaker get-workspace --workspace-id ${local.workspace_id}
          exit 1
        fi
        
        sleep 60
        ELAPSED=$((ELAPSED + 60))
      done

      if [ "$WORKSPACE_STATE" != "ACTIVE" ]; then
        echo "ERROR: Workspace failed to become active after $TIMEOUT seconds. Final state: $WORKSPACE_STATE"
        exit 1
      fi

      # Component type létrehozása
      echo "Creating component type..."
      cat > /tmp/component_type.json << EOF
{
  "description": "UR3 Robot Telemetry Component with Data Connector",
  "isSingleton": true,
  "functions": {
    "dataReader": {
      "implementedBy": {
        "lambda": {
          "arn": "${aws_lambda_function.ur3_data_processor.arn}"
        }
      },
      "isInherited": false,
      "scope": "ENTITY"
    }
  },
  "propertyDefinitions": {
    "joint1_position": {
      "dataType": { "type": "DOUBLE" },
      "isTimeSeries": true,
      "isStoredExternally": true,
      "defaultValue": { "doubleValue": 0.0 },
      "isRequiredInEntity": false
    },
    "joint2_position": {
      "dataType": { "type": "DOUBLE" },
      "isTimeSeries": true,
      "isStoredExternally": true,
      "defaultValue": { "doubleValue": 0.0 },
      "isRequiredInEntity": false
    },
    "joint3_position": {
      "dataType": { "type": "DOUBLE" },
      "isTimeSeries": true,
      "isStoredExternally": true,
      "defaultValue": { "doubleValue": 0.0 },
      "isRequiredInEntity": false
    },
    "robot_status": {
      "dataType": { "type": "STRING" },
      "isTimeSeries": true,
      "isStoredExternally": true,
      "defaultValue": { "stringValue": "IDLE" },
      "isRequiredInEntity": false
    },
    "joint1_target": {
      "dataType": { "type": "DOUBLE" },
      "isTimeSeries": false,
      "isStoredExternally": false,
      "defaultValue": { "doubleValue": 0.0 },
      "isRequiredInEntity": false
    },
    "joint2_target": {
      "dataType": { "type": "DOUBLE" },
      "isTimeSeries": false,
      "isStoredExternally": false,
      "defaultValue": { "doubleValue": 0.0 },
      "isRequiredInEntity": false
    },
    "joint3_target": {
      "dataType": { "type": "DOUBLE" },
      "isTimeSeries": false,
      "isStoredExternally": false,
      "defaultValue": { "doubleValue": 0.0 },
      "isRequiredInEntity": false
    }
  }
}
EOF

      aws iottwinmaker create-component-type \
        --workspace-id ${local.workspace_id} \
        --component-type-id com.ur3.robot.telemetry \
        --cli-input-json file:///tmp/component_type.json || {
        
        echo "Component type creation failed, checking if it already exists..."
        aws iottwinmaker get-component-type \
          --workspace-id ${local.workspace_id} \
          --component-type-id com.ur3.robot.telemetry && echo "Component type already exists"
      }

      sleep 15

      # Entity létrehozása
      echo "Creating entity..."
      cat > /tmp/entity.json << EOF
{
  "entityName": "UR3 Robot 001",
  "description": "UR3 Robot Digital Twin Entity",
  "components": {
    "ur3_telemetry": {
      "componentTypeId": "com.ur3.robot.telemetry",
      "properties": {
        "joint1_position": {
          "value": { "doubleValue": 0.0 }
        },
        "joint2_position": {
          "value": { "doubleValue": 0.0 }
        },
        "joint3_position": {
          "value": { "doubleValue": 0.0 }
        },
        "robot_status": {
          "value": { "stringValue": "IDLE" }
        },
        "joint1_target": {
          "value": { "doubleValue": 0.0 }
        },
        "joint2_target": {
          "value": { "doubleValue": 0.0 }
        },
        "joint3_target": {
          "value": { "doubleValue": 0.0 }
        }
      }
    }
  }
}
EOF

      aws iottwinmaker create-entity \
        --workspace-id ${local.workspace_id} \
        --entity-id ${local.entity_id} \
        --cli-input-json file:///tmp/entity.json || {
        
        echo "Entity creation failed, checking if it already exists..."
        aws iottwinmaker get-entity \
          --workspace-id ${local.workspace_id} \
          --entity-id ${local.entity_id} && echo "Entity already exists"
      }

      sleep 10

      # Scene létrehozása
      echo "Creating scene..."
      
      # Scene content feltöltése S3-ba
      cat > /tmp/scene_content.json << EOF
{
  "version": "1.0",
  "unit": "meters",
  "nodes": [
    {
      "name": "UR3_Robot_001",
      "transform": {
        "position": [0, 0, 0],
        "rotation": [0, 0, 0],
        "scale": [1, 1, 1]
      },
      "properties": {
        "entityId": "${local.entity_id}",
        "componentName": "ur3_telemetry"
      },
      "children": []
    }
  ],
  "rootNodeIndexes": [0]
}
EOF

      # Upload scene content to S3
      aws s3 cp /tmp/scene_content.json s3://${aws_s3_bucket.ur3_scene_bucket.bucket}/scenes/${local.scene_id}.json

      # Create scene in TwinMaker
      aws iottwinmaker create-scene \
        --workspace-id ${local.workspace_id} \
        --scene-id ${local.scene_id} \
        --content-location "arn:aws:s3:::${aws_s3_bucket.ur3_scene_bucket.bucket}/scenes/${local.scene_id}.json" \
        --description "UR3 Robot 3D Scene" || {
        
        echo "Scene creation failed, checking if it already exists..."
        aws iottwinmaker get-scene \
          --workspace-id ${local.workspace_id} \
          --scene-id ${local.scene_id} && echo "Scene already exists"
      }

      echo "TwinMaker resources created successfully!"
      
      # Cleanup temp files
      rm -f /tmp/component_type.json /tmp/entity.json /tmp/scene_content.json
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      echo "Cleaning up TwinMaker resources..."
      aws iottwinmaker delete-entity --workspace-id ur3-workspace-terraform --entity-id ur3-robot-001 2>/dev/null || true
      sleep 10
      aws iottwinmaker delete-component-type --workspace-id ur3-workspace-terraform --component-type-id com.ur3.robot.telemetry 2>/dev/null || true
      sleep 10
      aws iottwinmaker delete-scene --workspace-id ur3-workspace-terraform --scene-id ur3-robot-scene 2>/dev/null || true
      sleep 10
      aws iottwinmaker delete-workspace --workspace-id ur3-workspace-terraform 2>/dev/null || true
      echo "TwinMaker cleanup completed"
    EOT
  }
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