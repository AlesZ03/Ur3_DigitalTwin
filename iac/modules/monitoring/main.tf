resource "aws_iam_role" "cloud_processor_role" {
  name = "${var.project_name}-cloud-processor-role"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = ["lambda.amazonaws.com", "ec2.amazonaws.com"] } }]
  })
}

resource "aws_iam_role_policy" "cloud_processor_policy" {
  name = "${var.project_name}-cloud-processor-policy"
  role = aws_iam_role.cloud_processor_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], Resource = var.device_to_cloud_queue_arn },
      { Effect = "Allow", Action = ["sqs:SendMessage", "sqs:GetQueueAttributes"], Resource = var.cloud_to_device_queue_arn },
      { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], Resource = "arn:aws:logs:*:*:*" }
    ]
  })
}

resource "aws_cloudwatch_metric_alarm" "incoming_queue_depth" {
  alarm_name          = "${var.project_name}-incoming-queue-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = "300"
  statistic           = "Average"
  threshold           = "1000"
  dimensions          = { QueueName = var.device_to_cloud_queue_name }
}

resource "aws_cloudwatch_metric_alarm" "outgoing_queue_age" {
  alarm_name          = "${var.project_name}-outgoing-message-age"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = "300"
  statistic           = "Maximum"
  threshold           = "600"
  dimensions          = { QueueName = var.cloud_to_device_queue_name }
}

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}

resource "aws_sns_topic_subscription" "alert_email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}