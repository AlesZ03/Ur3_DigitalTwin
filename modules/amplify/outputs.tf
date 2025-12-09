# modules/amplify/outputs.tf

output "app_id" {
  description = "Az Amplify alkalmazás ID-ja"
  value       = aws_amplify_app.robot_control.id
}

output "app_arn" {
  description = "Az Amplify alkalmazás ARN-je"
  value       = aws_amplify_app.robot_control.arn
}

output "default_domain" {
  description = "Az Amplify alkalmazás alapértelmezett domain-je"
  value       = aws_amplify_app.robot_control.default_domain
}

output "branch_name" {
  description = "Az Amplify branch neve"
  value       = aws_amplify_branch.main.branch_name
}

output "app_url" {
  description = "Az Amplify alkalmazás teljes URL-je"
  value       = "https://${aws_amplify_branch.main.branch_name}.${aws_amplify_app.robot_control.default_domain}"
}

output "custom_domain" {
  description = "Custom domain URL (ha van)"
  value       = var.domain_name != null ? "https://${var.domain_prefix != "" ? "${var.domain_prefix}." : ""}${var.domain_name}" : null
}