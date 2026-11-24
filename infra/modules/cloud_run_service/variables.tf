variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "name" {
  type = string
}

variable "service_account" {
  description = "実行用サービスアカウントのメールアドレス"
  type        = string
}

variable "initial_image" {
  description = "作るときだけ使うイメージ。以後は CI が差し替え、Terraform は見ない"
  type        = string
}

variable "cpu" {
  type = string
}

variable "memory" {
  type = string
}

variable "cpu_idle" {
  description = "true は返事のあと CPU を絞る。false は常に割り当てる。CI の gcloud run deploy と揃える"
  type        = bool
  default     = true
}

variable "concurrency" {
  type = number
}

variable "min_instances" {
  type    = number
  default = 0
}

variable "max_instances" {
  description = "リビジョンの最大インスタンス数 (gcloud の --max-instances)"
  type        = number
}

variable "service_max_instances" {
  description = "サービス全体の最大インスタンス数"
  type        = number
}

variable "timeout_seconds" {
  type    = number
  default = 300
}

variable "execution_environment" {
  description = "EXECUTION_ENVIRONMENT_GEN2 など。null は Cloud Run の既定"
  type        = string
  default     = null
}

variable "startup_probe_path" {
  description = "HTTP の起動プローブのパス。null は TCP"
  type        = string
  default     = null
}

variable "env" {
  description = "環境変数。secret を入れたときは Secret Manager の latest を読む"
  type = map(object({
    value  = optional(string)
    secret = optional(string)
  }))
  default = {}
}

variable "invokers" {
  description = "roles/run.invoker を付けるメンバー (allUsers は公開)"
  type        = list(string)
  default     = []
}
