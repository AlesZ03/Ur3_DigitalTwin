output "api_url" {
  description = "The URL of the AppSync GraphQL API"
  value       = aws_appsync_graphql_api.ur3_api.uris["GRAPHQL"]
}

output "api_id" {
  description = "The ID of the AppSync API"
  value       = aws_appsync_graphql_api.ur3_api.id
}

output "api_key" {
  description = "The API Key for the AppSync API"
  value       = aws_appsync_api_key.ur3_api_key.key
  sensitive   = true
}