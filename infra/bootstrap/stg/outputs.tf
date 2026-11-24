# GitHub のリポジトリ変数 (Settings > Secrets and variables > Actions > Variables) に入れる値。
# どれも秘密の値ではない。

output "github_variables" {
  value = {
    GCP_STG_PROJECT_ID   = local.project_id
    GCP_STG_WIF_PROVIDER = google_iam_workload_identity_pool_provider.github_actions.name
    GCP_STG_PLAN_SA      = google_service_account.plan.email
    GCP_STG_DEPLOY_SA    = google_service_account.deploy.email
  }
}
