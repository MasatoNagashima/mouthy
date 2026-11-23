# GitHub Actions が STG (mouthy-stg) を触るための土台。オーナーが手元で一度だけ apply する。
# CI はここを apply しない。自分の権限を自分で広げられないようにするため。
# 本番プロジェクトは作らない。

locals {
  project              = jsondecode(file("${path.module}/../../project.json"))
  project_id           = local.project.project_id
  region               = local.project.region
  github_repository    = local.project.github_repository
  github_repository_id = local.project.github_repository_id
  github_owner_id      = local.project.github_owner_id

  pool_name = google_iam_workload_identity_pool.github.name

  plan_project_roles = [
    "roles/iam.securityReviewer",
    "roles/iam.serviceAccountViewer",
    "roles/run.viewer",
    "roles/secretmanager.viewer",
    "roles/storage.bucketViewer",
    "roles/artifactregistry.reader",
    "roles/serviceusage.serviceUsageConsumer",
  ]

  deploy_project_roles = [
    "roles/run.admin",
    "roles/iam.securityAdmin",
    "roles/iam.serviceAccountAdmin",
    "roles/secretmanager.viewer",
    "roles/storage.admin",
    "roles/artifactregistry.admin",
    "roles/cloudbuild.builds.editor",
    "roles/logging.viewer",
    "roles/serviceusage.serviceUsageConsumer",
  ]
}

resource "google_project_service" "sts" {
  project            = local.project_id
  service            = "sts.googleapis.com"
  disable_on_destroy = false
}

resource "google_storage_bucket" "tfstate" {
  project                     = local.project_id
  name                        = "mouthy-stg-tfstate"
  location                    = "ASIA-NORTHEAST1"
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 20
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "google_iam_workload_identity_pool" "github" {
  project                   = local.project_id
  workload_identity_pool_id = "github"
  display_name              = "GitHub Actions"
  description               = "GitHub Actions (${local.github_repository})"
}

resource "google_iam_workload_identity_pool_provider" "github_actions" {
  project                            = local.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions"
  display_name                       = "GitHub Actions OIDC"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
    "attribute.event_name" = "assertion.event_name"
    # attribute.ref の値は refs/heads/main のようにスラッシュを含む。
    # principalSet の経路もスラッシュ区切りのため、ブランチ名だけを取り出す。
    "attribute.branch" = "assertion.ref.extract('refs/heads/{branch}')"
  }

  attribute_condition = join(" && ", [
    "assertion.repository == '${local.github_repository}'",
    "assertion.repository_id == '${local.github_repository_id}'",
    "assertion.repository_owner_id == '${local.github_owner_id}'",
  ])

  depends_on = [google_project_service.sts]
}

resource "google_service_account" "plan" {
  project      = local.project_id
  account_id   = "gha-stg-plan"
  display_name = "GitHub Actions STG plan"
  description  = "PR の terraform plan (読み取りだけ)。${local.github_repository} のどのブランチからも使える"
}

resource "google_project_iam_member" "plan" {
  for_each = toset(local.plan_project_roles)

  project = local.project_id
  role    = each.value
  member  = google_service_account.plan.member
}

resource "google_storage_bucket_iam_member" "plan_state_reader" {
  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.objectViewer"
  member = google_service_account.plan.member
}

resource "google_service_account_iam_member" "plan_wif" {
  service_account_id = google_service_account.plan.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${local.pool_name}/attribute.repository/${local.github_repository}"
}

resource "google_service_account" "deploy" {
  project      = local.project_id
  account_id   = "gha-stg-deploy"
  display_name = "GitHub Actions STG deploy"
  description  = "main への push で terraform apply と Cloud Run のデプロイ。${local.github_repository} の main からだけ使える"
}

resource "google_project_iam_member" "deploy" {
  for_each = toset(local.deploy_project_roles)

  project = local.project_id
  role    = each.value
  member  = google_service_account.deploy.member
}

resource "google_storage_bucket_iam_member" "deploy_state" {
  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.objectAdmin"
  member = google_service_account.deploy.member
}

# main ブランチの push と手動実行だけ。PR やほかのブランチのトークンでは使えない。
resource "google_service_account_iam_member" "deploy_wif" {
  service_account_id = google_service_account.deploy.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${local.pool_name}/attribute.branch/main"
}
