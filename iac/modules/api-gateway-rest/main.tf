# modules/api-gateway-rest/main.tf

# REST API
resource "aws_api_gateway_rest_api" "api" {
  name        = var.api_name
  description = var.api_description

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = var.tags
}

# /logs resource
resource "aws_api_gateway_resource" "logs" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "logs"
}

# /command resource (új)
resource "aws_api_gateway_resource" "command" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "command"
}

# GET /logs method
resource "aws_api_gateway_method" "get_logs" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.logs.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "get_logs_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.logs.id
  http_method             = aws_api_gateway_method.get_logs.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.read_logs.invoke_arn
}

# OPTIONS method for CORS
resource "aws_api_gateway_method" "options_logs" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.logs.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_logs" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.logs.id
  http_method = aws_api_gateway_method.options_logs.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "options_logs_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.logs.id
  http_method = aws_api_gateway_method.options_logs.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "options_logs" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.logs.id
  http_method = aws_api_gateway_method.options_logs.http_method
  status_code = aws_api_gateway_method_response.options_logs_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# POST /command method (új)
resource "aws_api_gateway_method" "post_command" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.command.id
  http_method   = "POST"
  authorization = "NONE"
}

# Lambda integration for POST /command
resource "aws_api_gateway_integration" "post_command_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.command.id
  http_method             = aws_api_gateway_method.post_command.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.send_command.invoke_arn
}

# OPTIONS /command for CORS
resource "aws_api_gateway_method" "options_command" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.command.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_command" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.command.id
  http_method = aws_api_gateway_method.options_command.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "options_command_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.command.id
  http_method = aws_api_gateway_method.options_command.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "options_command" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.command.id
  http_method = aws_api_gateway_method.options_command.http_method
  status_code = aws_api_gateway_method_response.options_command_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# --- /command/quick endpoint ---
resource "aws_api_gateway_resource" "command_quick" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_resource.command.id
  path_part   = "quick"
}

# GET /command/quick method
resource "aws_api_gateway_method" "get_command_quick" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.command_quick.id
  http_method   = "GET"
  authorization = "NONE"
}

# Lambda integration for GET /command/quick
resource "aws_api_gateway_integration" "get_command_quick_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.command_quick.id
  http_method             = aws_api_gateway_method.get_command_quick.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.send_command.invoke_arn
}

# OPTIONS /command/quick for CORS
resource "aws_api_gateway_method" "options_command_quick" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.command_quick.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_command_quick" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.command_quick.id
  http_method = aws_api_gateway_method.options_command_quick.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "options_command_quick_200" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.command_quick.id
  http_method = aws_api_gateway_method.options_command_quick.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "options_command_quick" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.command_quick.id
  http_method = aws_api_gateway_method.options_command_quick.http_method
  status_code = aws_api_gateway_method_response.options_command_quick_200.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# Deployment
resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  depends_on = [
    aws_api_gateway_integration.get_logs_lambda,
    aws_api_gateway_integration.options_logs,
    aws_api_gateway_integration.post_command_lambda,
    aws_api_gateway_integration.options_command,
    aws_api_gateway_integration.get_command_quick_lambda,
    aws_api_gateway_integration.options_command_quick
  ]

  lifecycle {
    create_before_destroy = true
  }

  triggers = {
    redeployment = sha1(jsonencode(
      [
        aws_api_gateway_integration.get_logs_lambda.uri,
        aws_api_gateway_integration.options_logs.id,
        aws_api_gateway_integration.post_command_lambda.uri,
        aws_api_gateway_integration.options_command.id,
        aws_api_gateway_integration.get_command_quick_lambda.uri,
        aws_api_gateway_integration.options_command_quick.id,
      ]
    ))
  }
}

# Stage
resource "aws_api_gateway_stage" "stage" {
  deployment_id = aws_api_gateway_deployment.deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = var.stage_name

  tags = var.tags
}

# Lambda permission for logs endpoint

resource "aws_lambda_permission" "api_gateway_logs" {
  statement_id  = "AllowAPIGatewayInvokeLogs"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.read_logs.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

# Lambda permission for command endpoint (POST /command and GET /command/quick)
resource "aws_lambda_permission" "api_gateway_command_lambda" {
  statement_id  = "AllowAPIGatewayInvokeCommandLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.send_command.function_name # This is for the send_command lambda
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*" # Allow all methods on all paths for this API
}

data "archive_file" "read_logs_lambda" {
  type        = "zip"
  output_path = "${path.root}/lambda-dist/read-logs.zip"
  source {
    content  = file("${path.root}/lambda/api/read_logs.py")
    filename = "index.py"
  }
}

data "archive_file" "command_lambda" {
  type        = "zip"
  output_path = "${path.root}/lambda-dist/send-command.zip"
  source {
    content  = file("${path.root}/lambda/api/send_command.py")
    filename = "index.py"
  }
}


resource "aws_lambda_function" "read_logs" {
  filename         = data.archive_file.read_logs_lambda.output_path
  function_name    = "${var.api_name}-read-logs"
  role             = var.lambda_execution_role_arn
  handler          = "index.lambda_handler"
  runtime          = "python3.11"
  timeout          = 30
  memory_size      = 512
  source_code_hash = data.archive_file.read_logs_lambda.output_base64sha256


  environment {
    variables = {
      TABLE_NAME  = var.telemetry_table_name
      BUCKET_NAME = var.firehose_s3_bucket_name
    }
  }
  tags = var.tags
}
resource "aws_cloudwatch_log_group" "read_logs_lambda_log" {
  name              = "/aws/lambda/${aws_lambda_function.read_logs.function_name}"
  retention_in_days = 7
  tags              = var.tags
}

resource "aws_lambda_function" "send_command" {
  filename         = data.archive_file.command_lambda.output_path
  function_name    = "${var.api_name}-send-command"
  role             = var.lambda_execution_role_arn
  handler          = "index.lambda_handler"
  runtime          = "python3.10"
  timeout          = 30
  source_code_hash = data.archive_file.command_lambda.output_base64sha256
  layers           = [aws_lambda_layer_version.robotics_math_layer.arn]
  memory_size      = 512
  environment { variables = { COMMAND_QUEUE_URL = var.command_queue_url } }
  tags = var.tags
}
resource "aws_s3_object" "robotics_layer_zip" {
  bucket = var.s3_bucket_name
  key    = "layers/robotics_layer.zip"
  source = "${path.root}/lambda/layers/robotics_layer.zip"


  etag = filemd5("${path.root}/lambda/layers/robotics_layer.zip")
}

resource "aws_lambda_layer_version" "robotics_math_layer" {
  layer_name          = "robotics_math_toolbox"
  compatible_runtimes = ["python3.11", "python3.12"]
  description         = "NumPy, RoboticsToolbox and SpatialMath for UR3 IK"

  s3_bucket = aws_s3_object.robotics_layer_zip.bucket
  s3_key    = aws_s3_object.robotics_layer_zip.key


  source_code_hash = filebase64sha256("${path.root}/lambda/layers/robotics_layer.zip")
}
resource "aws_cloudwatch_log_group" "send_command_lambda" {
  name              = "/aws/lambda/${aws_lambda_function.send_command.function_name}"
  retention_in_days = 7
  tags              = var.tags
}

