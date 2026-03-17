# --- Timestream Adatbázis és Tábla ---
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.root}/lambda/timestream/writer.py"
  output_path = "${path.root}/lambda-dist/writer.zip"
}

resource "aws_timestreamwrite_database" "robot_db" {
  database_name = "${var.project_name}-db"
}

resource "aws_timestreamwrite_table" "robot_telemetry" {
  database_name = aws_timestreamwrite_database.robot_db.database_name
  table_name    = "robot_logs"

  retention_properties {
    memory_store_retention_period_in_hours  = 6
    magnetic_store_retention_period_in_days = 14
  }
}

# --- Lambda Függvény (A Firehose-ból Timestream-be író híd) ---
resource "aws_iam_role" "lambda_writer_role" {
  name = "${var.project_name}-timestream-writer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}
resource "aws_iam_role_policy" "lambda_writer_permissions" {
  name = "${var.project_name}-timestream-writer-policy"
  role = aws_iam_role.lambda_writer_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {

        Effect = "Allow"
        Action = [
          "timestream:WriteRecords",
          "timestream:DescribeEndpoints"
        ]
        Resource = "*"
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
resource "aws_lambda_function" "firehose_to_timestream" {
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  function_name = "${var.project_name}-firehose-to-timestream"
  role          = aws_iam_role.lambda_writer_role.arn

  handler = "writer.handler"

  runtime = "python3.9"
  timeout = 60

  environment {
    variables = {
      DB_NAME    = aws_timestreamwrite_database.robot_db.database_name
      TABLE_NAME = aws_timestreamwrite_table.robot_telemetry.table_name
    }
  }
}
resource "aws_lambda_permission" "allow_firehose" {
  statement_id  = "AllowExecutionFromFirehose"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.firehose_to_timestream.function_name
  principal     = "firehose.amazonaws.com"
  source_arn    = var.firehose_stream_arn
}