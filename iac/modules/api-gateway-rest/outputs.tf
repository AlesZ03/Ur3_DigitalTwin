# modules/api-gateway-rest/outputs.tf

output "api_id" {
  description = "REST API ID"
  value       = aws_api_gateway_rest_api.api.id
}

output "api_endpoint" {
  description = "API endpoint URL"
  value       = "${aws_api_gateway_stage.stage.invoke_url}"
}

output "api_url" {
  description = "Teljes API URL a logs endpoint-tal"
  value       = "${aws_api_gateway_stage.stage.invoke_url}/logs"
}

output "command_api_url" {
  description = "Teljes API URL a command endpoint-tal"
  value       = "${aws_api_gateway_stage.stage.invoke_url}/command"
}

output "command_quick_api_url" {
  description = "Teljes API URL a command/quick endpoint-tal"
  value       = "${aws_api_gateway_stage.stage.invoke_url}/command/quick"
}

output "execution_arn" {
  description = "API Gateway execution ARN"
  value       = aws_api_gateway_rest_api.api.execution_arn
}