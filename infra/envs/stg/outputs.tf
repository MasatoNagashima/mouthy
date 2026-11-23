output "api_url" {
  description = "iOS の API_BASE_URL (ios/Config/stg/Mouthy.xcconfig) に入れる"
  value       = module.api.uri
}

output "project_id" {
  value = local.project_id
}
