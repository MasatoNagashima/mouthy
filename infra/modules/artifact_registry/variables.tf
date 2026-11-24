variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "repository_id" {
  type = string
}

variable "cleanup_policy_file" {
  description = "gcloud artifacts repositories set-cleanup-policies と同じ JSON"
  type        = string
}
