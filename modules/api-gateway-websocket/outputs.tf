output "websocket_api_id" {
  description = "The ID of the WebSocket API."
  value       = aws_apigatewayv2_api.websocket_api.id
}

output "websocket_api_invoke_url" {
  description = "The invoke URL for the WebSocket API stage."
  value       = aws_apigatewayv2_stage.websocket_stage.invoke_url
}

