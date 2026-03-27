# --- DynamoDB Tábla ---
resource "aws_dynamodb_table" "telemetry_db" {
  name         = "${var.project_name}-telemetry"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "robot_id"
  range_key    = "timestamp"

  attribute {
    name = "robot_id"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "N"
  }

  tags = var.tags
}

# --- Lambda IAM Role és Policy ---
resource "aws_iam_role" "lambda_exec_role" {
  name = "${var.project_name}-dynamo-writer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "lambda_dynamo_policy" {
  name = "${var.project_name}-dynamo-writer-policy"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:BatchWriteItem"
        ]
        Resource = aws_dynamodb_table.telemetry_db.arn
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


resource "aws_lambda_permission" "allow_firehose" {
  statement_id  = "AllowExecutionFromFirehose"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dynamo_writer.function_name
  principal     = "firehose.amazonaws.com"
}


data "archive_file" "dynamo_writer_zip" {
  type        = "zip"
  output_path = "${path.root}/lambda-dist/dynamo_writer.zip"
  source {
    content  = file("${path.root}/${var.lambda_source_path}")
    filename = "index.py"
  }
}

resource "aws_lambda_function" "dynamo_writer" {
  function_name    = "${var.project_name}-dynamo-writer"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "index.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.dynamo_writer_zip.output_path
  source_code_hash = data.archive_file.dynamo_writer_zip.output_base64sha256
  timeout          = 60

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.telemetry_db.name
    }
  }

  tags = var.tags
}