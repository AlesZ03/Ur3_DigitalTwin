
# AWS Console URLs


output "iot_test_console_url" {
  description = "AWS IoT Core Test Console URL"
  value       = "https://console.aws.amazon.com/iot/home?region=${var.aws_region}#/test"
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

output "api_logs_url" {
  description = "REST API URL a logok lekéréséhez"
  value       = module.logs_api.api_url
  value       = "${aws_api_gateway_stage.ur3_api_stage.invoke_url}/logs"
}

output "api_command_url" {
  description = "REST API URL parancsok küldéséhez"
  value       = module.logs_api.command_api_url
  value       = "${aws_api_gateway_stage.ur3_api_stage.invoke_url}/command"
}

output "amplify_app_url" {
  description = "Amplify hosted frontend URL"
  value       = "https://${var.amplify_branch_name}.${aws_amplify_app.github_connected.default_domain}"
  sensitive   = true
}



