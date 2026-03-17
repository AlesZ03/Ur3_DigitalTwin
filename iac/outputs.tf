

output "iot_endpoint" {
  description = "The endpoint for the AWS IoT Core service. Copy this to your core-test.py and ur-rtde.py scripts."
  value       = data.aws_iot_endpoint.current.endpoint_address
}

output "iot_thing_name" {
  description = "The name of the created IoT Thing."
  value       = module.iot_core.thing_name
}