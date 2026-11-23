output "name" {
  value = google_cloud_run_v2_service.this.name
}

output "uri" {
  description = "Cloud Run の URL。iOS の API_BASE_URL に入れる"
  value       = google_cloud_run_v2_service.this.uri
}
