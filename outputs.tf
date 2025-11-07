# Basic resource information
output "workspace_id" {
  description = "TwinMaker Workspace ID"
  value       = local.workspace_id
}

output "entity_id" {
  description = "TwinMaker Entity ID"
  value       = local.entity_id
}

output "scene_id" {
  description = "TwinMaker Scene ID"
  value       = local.scene_id
}

output "s3_bucket_name" {
  description = "S3 bucket name for TwinMaker assets"
  value       = aws_s3_bucket.ur3_scene_bucket.bucket
}

output "lambda_function_name" {
  description = "Lambda function name for data processing"
  value       = aws_lambda_function.ur3_data_processor.function_name
}

output "lambda_function_arn" {
  description = "Lambda function ARN"
  value       = aws_lambda_function.ur3_data_processor.arn
}



output "iam_role_arn" {
  description = "TwinMaker execution role ARN"
  value       = aws_iam_role.twinmaker_execution_role.arn
}

# AWS Console URLs
output "twinmaker_console_url" {
  description = "AWS TwinMaker Console URL for the workspace"
  value       = "https://${var.aws_region}.console.aws.amazon.com/iottwinmaker/home?region=${var.aws_region}#/workspaces/${local.workspace_id}"
}

output "twinmaker_dashboard_url" {
  description = "Direct link to TwinMaker workspace dashboard"
  value       = "https://console.aws.amazon.com/iottwinmaker/home?region=${var.aws_region}#/workspaces/${local.workspace_id}/dashboard"
}

output "iot_test_console_url" {
  description = "AWS IoT Core Test Console URL"
  value       = "https://console.aws.amazon.com/iot/home?region=${var.aws_region}#/test"
}

output "lambda_console_url" {
  description = "AWS Lambda Console URL for the data processor function"
  value       = "https://console.aws.amazon.com/lambda/home?region=${var.aws_region}#/functions/${aws_lambda_function.ur3_data_processor.function_name}"
}

output "s3_console_url" {
  description = "AWS S3 Console URL for the scene bucket"
  value       = "https://s3.console.aws.amazon.com/s3/buckets/${aws_s3_bucket.ur3_scene_bucket.bucket}"
}

# IoT Topics and Resources
output "iot_thing_name" {
  description = "IoT Thing name for the UR3 robot"
  value       = aws_iot_thing.ur3_robot_thing.name
}

output "iot_policy_name" {
  description = "IoT Policy name for the UR3 robot"
  value       = aws_iot_policy.ur3_robot_policy.name
}

output "telemetry_topic" {
  description = "IoT topic for sending telemetry data"
  value       = "ur3/robot/telemetry"
}

output "command_topic" {
  description = "IoT topic for receiving robot commands"
  value       = "ur3/robot/commands"
}

# Testing information
output "test_commands" {
  description = "Example commands for testing the system"
  value = {
    send_telemetry = "aws iot-data publish --topic 'ur3/robot/telemetry' --payload '{\"joint1_position\": 1.57, \"joint2_position\": -0.78, \"joint3_position\": 0.78, \"robot_status\": \"MOVING\"}'"
    
    test_lambda = "aws lambda invoke --function-name ${aws_lambda_function.ur3_data_processor.function_name} --payload '{\"joint1_position\": 0.5, \"joint2_position\": -0.5, \"joint3_position\": 0.5, \"robot_status\": \"IDLE\"}' response.json"
    
    check_entity = "aws iottwinmaker get-entity --workspace-id ${local.workspace_id} --entity-id ${local.entity_id}"
    
    get_property = "aws iottwinmaker get-property-value --workspace-id ${local.workspace_id} --entity-id ${local.entity_id} --component-name ur3_telemetry --property-name joint1_position"
    
    list_scenes = "aws iottwinmaker list-scenes --workspace-id ${local.workspace_id}"
  }
}

# Component and Entity information
output "component_type_id" {
  description = "TwinMaker Component Type ID"
  value       = "com.ur3.robot.telemetry"
}

output "component_name" {
  description = "Component name in the entity"
  value       = "ur3_telemetry"
}

# Region and Account
output "aws_region" {
  description = "AWS Region where resources are deployed"
  value       = var.aws_region
}

output "aws_account_id" {
  description = "AWS Account ID"
  value       = data.aws_caller_identity.current.account_id
}



output "s3_bucket_arn" {
  description = "Az S3 bucket ARN-je"
  value       = module.s3_robot_data.bucket_arn
}

output "s3_bucket_id" {
  description = "Az S3 bucket ID-ja"
  value       = module.s3_robot_data.bucket_id
}



output "lambda_role_arn" {
  description = "A Lambda IAM role ARN-je"
  value       = module.lambda_robot_processor.role_arn
}

output "lambda_log_group_name" {
  description = "A Lambda CloudWatch Log Group neve"
  value       = module.lambda_robot_processor.log_group_name
}