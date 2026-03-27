# --- S3 Bucket az adatok tárolására ---
resource "aws_s3_bucket" "telemetry_bucket" {
  bucket        = "${lower(replace(var.project_name, "_", "-"))}-telemetry-storage-${var.account_id}"
  force_destroy = true

  tags = var.tags
}

# --- IAM Role a Firehose-nak ---
resource "aws_iam_role" "firehose_role" {
  name = "${var.project_name}-firehose-s3-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "firehose.amazonaws.com" }
    }]
  })
}

# IAM Policy a Firehose-nak: engedély az S3 írásra és a naplózásra
resource "aws_iam_role_policy" "firehose_s3_policy" {
  name = "${var.project_name}-firehose-s3-policy"
  role = aws_iam_role.firehose_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.telemetry_bucket.arn,
          "${aws_s3_bucket.telemetry_bucket.arn}/*"
        ]
      }
    ]
  })
}
resource "aws_kinesis_firehose_delivery_stream" "telemetry_stream" {
  name        = "${var.project_name}-telemetry-stream"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose_role.arn
    bucket_arn = aws_s3_bucket.telemetry_bucket.arn

    buffering_size     = 1
    buffering_interval = 60

    compression_format = "UNCOMPRESSED"

    prefix = "data/!{timestamp:yyyy/MM/dd/}"

    error_output_prefix = "errors/!{firehose:error-output-type}/!{timestamp:yyyy/MM/dd/}"

    file_extension = ".json"
   
  }
}

# --- IoT Topic Rule ---
resource "aws_iam_role" "iot_firehose_role" {
  name = "${var.project_name}-iot-firehose-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "iot.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "iot_firehose_policy" {
  name = "${var.project_name}-iot-firehose-policy"
  role = aws_iam_role.iot_firehose_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "firehose:PutRecord"
      Resource = aws_kinesis_firehose_delivery_stream.telemetry_stream.arn
    }]
  })
}

resource "aws_iot_topic_rule" "telemetry_to_firehose" {
  name        = "${replace(var.project_name, "-", "_")}_logs_to_firehose"
  description = "Robot logok továbbítása S3-ba Firehose-on keresztül"
  enabled     = true
  sql         = "SELECT *, topic() as source_topic FROM 'ur3/logs'"
  sql_version = "2016-03-23"

  firehose {
    delivery_stream_name = aws_kinesis_firehose_delivery_stream.telemetry_stream.name
    role_arn             = aws_iam_role.iot_firehose_role.arn
  }
}