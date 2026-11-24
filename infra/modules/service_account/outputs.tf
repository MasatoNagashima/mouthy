output "email" {
  value = google_service_account.this.email
}

output "member" {
  description = "serviceAccount:<email>"
  value       = google_service_account.this.member
}

output "name" {
  value = google_service_account.this.name
}
