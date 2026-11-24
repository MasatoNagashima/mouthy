# STG (mouthy-stg) のインフラ。本番プロジェクトは無い。
# Cloud Run のイメージと mouthy-commit ラベルは CI が差し替えるので見ない。
# Secret Manager の値 (OpenAI の鍵) は Terraform に置かない。

locals {
  project        = jsondecode(file("${path.module}/../../project.json"))
  project_id     = local.project.project_id
  region         = local.project.region
  registry       = "${local.region}-docker.pkg.dev/${local.project_id}/mouthy"
  openai_secret  = "openai-api-key"
  session_secret = "mouthy-session-secret"
  google_client  = jsondecode(file("${path.module}/../../google-client.json"))
}

resource "google_project_service" "apis" {
  for_each = toset([
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "secretmanager.googleapis.com",
    "cloudbuild.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "storage.googleapis.com",
  ])

  project            = local.project_id
  service            = each.value
  disable_on_destroy = false
}

module "api_sa" {
  source = "../../modules/service_account"

  project_id   = local.project_id
  account_id   = "mouthy-api"
  display_name = "Mouthy API"
  project_roles = [
    "roles/secretmanager.secretAccessor",
  ]

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret" "openai" {
  project   = local.project_id
  secret_id = local.openai_secret

  replication {
    user_managed {
      replicas {
        location = local.region
      }
    }
  }

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_iam_member" "openai_accessor" {
  project   = local.project_id
  secret_id = google_secret_manager_secret.openai.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = module.api_sa.member
}

# 値（セッション署名の秘密）は Terraform に置かない。入れ物だけ作る。
# バージョンが無いと、この秘密を参照する Cloud Run リビジョンは起動しない。
resource "google_secret_manager_secret" "session" {
  project   = local.project_id
  secret_id = local.session_secret

  replication {
    user_managed {
      replicas {
        location = local.region
      }
    }
  }

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret_iam_member" "session_accessor" {
  project   = local.project_id
  secret_id = google_secret_manager_secret.session.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = module.api_sa.member
}

module "registry" {
  source = "../../modules/artifact_registry"

  project_id          = local.project_id
  region              = local.region
  repository_id       = "mouthy"
  cleanup_policy_file = "${path.module}/../../artifact-registry/cleanup-policy.json"

  depends_on = [google_project_service.apis]
}

# 値は CI のデプロイ (ci/stg_deploy.sh の gcloud run deploy) と揃えている。
# 片方を変えるときは、もう片方も変える。
module "api" {
  source = "../../modules/cloud_run_service"

  project_id            = local.project_id
  region                = local.region
  name                  = "mouthy-api"
  service_account       = module.api_sa.email
  initial_image         = "${local.registry}/api:stg"
  cpu                   = "1"
  memory                = "512Mi"
  cpu_idle              = true
  concurrency           = 80
  max_instances         = 3
  service_max_instances = 20
  startup_probe_path    = "/api/health"
  env = {
    HOST                    = { value = "0.0.0.0" }
    NODE_ENV                = { value = "production" }
    OPENAI_API_KEY          = { secret = local.openai_secret }
    MOUTHY_SESSION_SECRET   = { secret = local.session_secret }
    MOUTHY_APPLE_AUDIENCE   = { value = "com.mouthy.stg" }
    MOUTHY_GOOGLE_CLIENT_ID = { value = local.google_client.iosClientId }
  }
  invokers = ["allUsers"]

  depends_on = [
    module.registry,
    google_secret_manager_secret.openai,
    google_secret_manager_secret.session,
  ]
}

# デプロイ用 SA は bootstrap が作る。ここは「その SA が API として動ける」「イメージを読める」だけを足す。
resource "google_service_account_iam_member" "deploy_act_as_api" {
  service_account_id = module.api_sa.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:gha-stg-deploy@${local.project_id}.iam.gserviceaccount.com"
}

resource "google_service_account_iam_member" "deploy_act_as_compute" {
  count = local.project.project_number == "0" ? 0 : 1

  service_account_id = "projects/${local.project_id}/serviceAccounts/${local.project.project_number}-compute@developer.gserviceaccount.com"
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:gha-stg-deploy@${local.project_id}.iam.gserviceaccount.com"
}

resource "google_artifact_registry_repository_iam_member" "plan_reader" {
  project    = local.project_id
  location   = local.region
  repository = module.registry.repository_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:gha-stg-plan@${local.project_id}.iam.gserviceaccount.com"
}

resource "google_artifact_registry_repository_iam_member" "deploy_admin" {
  project    = local.project_id
  location   = local.region
  repository = module.registry.repository_id
  role       = "roles/artifactregistry.admin"
  member     = "serviceAccount:gha-stg-deploy@${local.project_id}.iam.gserviceaccount.com"
}
