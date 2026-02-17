resource "aws_apigatewayv2_api" "websocket_api" {
  name                       = var.api_name
  protocol_type              = "WEBSOCKET"
  route_selection_expression = "$request.body.action"
  tags                       = var.tags
}

# --- $connect route ---
resource "aws_apigatewayv2_integration" "connect_integration" {
  api_id           = aws_apigatewayv2_api.websocket_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = var.connect_lambda_invoke_arn
}

resource "aws_apigatewayv2_route" "connect_route" {
  api_id    = aws_apigatewayv2_api.websocket_api.id
  route_key = "$connect"
  target    = "integrations/${aws_apigatewayv2_integration.connect_integration.id}"
}

# --- $disconnect route ---
resource "aws_apigatewayv2_integration" "disconnect_integration" {
  api_id           = aws_apigatewayv2_api.websocket_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = var.disconnect_lambda_invoke_arn
}

resource "aws_apigatewayv2_route" "disconnect_route" {
  api_id    = aws_apigatewayv2_api.websocket_api.id
  route_key = "$disconnect"
  target    = "integrations/${aws_apigatewayv2_integration.disconnect_integration.id}"
}

# --- $default route (for messages from client) ---
resource "aws_apigatewayv2_integration" "default_integration" {
  api_id           = aws_apigatewayv2_api.websocket_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = var.default_lambda_invoke_arn
}

resource "aws_apigatewayv2_route" "default_route" {
  api_id    = aws_apigatewayv2_api.websocket_api.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.default_integration.id}"
}

# --- Deployment and Stage ---
resource "aws_apigatewayv2_deployment" "websocket_deployment" {
  api_id = aws_apigatewayv2_api.websocket_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_apigatewayv2_route.connect_route,
      aws_apigatewayv2_route.disconnect_route,
      aws_apigatewayv2_route.default_route,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_apigatewayv2_stage" "websocket_stage" {
  api_id        = aws_apigatewayv2_api.websocket_api.id
  name          = "prod"
  deployment_id = aws_apigatewayv2_deployment.websocket_deployment.id
  tags          = var.tags
}

# --- Lambda Permissions ---
resource "aws_lambda_permission" "allow_connect" {
  statement_id  = "AllowAPIGatewayWSConnect"
  action        = "lambda:InvokeFunction"
  function_name = var.connect_lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.websocket_api.execution_arn}/*"
}

resource "aws_lambda_permission" "allow_disconnect" {
  statement_id  = "AllowAPIGatewayWSDisconnect"
  action        = "lambda:InvokeFunction"
  function_name = var.disconnect_lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.websocket_api.execution_arn}/*"
}

resource "aws_lambda_permission" "allow_default" {
  statement_id  = "AllowAPIGatewayWSDefault"
  action        = "lambda:InvokeFunction"
  function_name = var.default_lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.websocket_api.execution_arn}/*"
}
