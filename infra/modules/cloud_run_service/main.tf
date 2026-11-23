# Cloud Run (v2) のサービス 1 つと、その呼び出し権限。
# イメージと mouthy-commit ラベルは CI が gcloud run deploy で差し替えるので、
# Terraform はそこを見ない (ignore_changes)。

resource "google_cloud_run_v2_service" "this" {
  project             = var.project_id
  location            = var.region
  name                = var.name
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = true

  scaling {
    min_instance_count = 0
    max_instance_count = var.service_max_instances
  }

  template {
    service_account                  = var.service_account
    max_instance_request_concurrency = var.concurrency
    timeout                          = "${var.timeout_seconds}s"
    execution_environment            = var.execution_environment

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    containers {
      image = var.initial_image

      ports {
        name           = "http1"
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
        cpu_idle          = var.cpu_idle
        startup_cpu_boost = true
      }

      dynamic "env" {
        for_each = var.env
        content {
          name  = env.key
          value = env.value.secret == null ? env.value.value : null

          dynamic "value_source" {
            for_each = env.value.secret == null ? [] : [env.value.secret]
            content {
              secret_key_ref {
                secret  = value_source.value
                version = "latest"
              }
            }
          }
        }
      }

      dynamic "startup_probe" {
        for_each = var.startup_probe_path == null ? [] : [var.startup_probe_path]
        content {
          initial_delay_seconds = 0
          timeout_seconds       = 3
          period_seconds        = 5
          failure_threshold     = 60
          http_get {
            path = startup_probe.value
            port = 8080
          }
        }
      }

      dynamic "startup_probe" {
        for_each = var.startup_probe_path == null ? [1] : []
        content {
          initial_delay_seconds = 0
          timeout_seconds       = 240
          period_seconds        = 240
          failure_threshold     = 1
          tcp_socket {
            port = 8080
          }
        }
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  lifecycle {
    ignore_changes = [
      client,
      client_version,
      labels,
      template[0].labels,
      template[0].revision,
      template[0].containers[0].image,
    ]
  }
}

resource "google_cloud_run_v2_service_iam_member" "invoker" {
  for_each = toset(var.invokers)

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.this.name
  role     = "roles/run.invoker"
  member   = each.value
}
