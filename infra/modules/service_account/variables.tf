variable "project_id" {
  type = string
}

variable "account_id" {
  type = string
}

variable "display_name" {
  type = string
}

variable "description" {
  type    = string
  default = null
}

variable "project_roles" {
  description = "プロジェクトに付けるロール (roles/...)"
  type        = list(string)
  default     = []
}
