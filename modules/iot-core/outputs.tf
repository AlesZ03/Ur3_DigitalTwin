# modules/iot-core/outputs.tf

output "thing_name" {
  description = "The name of the created IoT Thing."
  value       = aws_iot_thing.ur3_robot.name
}

output "thing_arn" {
  description = "The ARN of the created IoT Thing."
  value       = aws_iot_thing.ur3_robot.arn
}