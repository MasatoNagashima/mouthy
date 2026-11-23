# Docker のイメージ置き場。クリーンアップポリシーは
# infra/artifact-registry/cleanup-policy.json (gcloud と同じ形式) から読む。

locals {
  policies = jsondecode(file(var.cleanup_policy_file))
}

resource "google_artifact_registry_repository" "this" {
  project                = var.project_id
  location               = var.region
  repository_id          = var.repository_id
  format                 = "DOCKER"
  cleanup_policy_dry_run = false

  docker_config {
    immutable_tags = false
  }

  dynamic "cleanup_policies" {
    for_each = { for p in local.policies : p.name => p }
    content {
      id     = cleanup_policies.key
      action = upper(cleanup_policies.value.action.type)

      dynamic "condition" {
        for_each = try([cleanup_policies.value.condition], [])
        content {
          tag_state             = try(upper(condition.value.tagState), null)
          tag_prefixes          = try(condition.value.tagPrefixes, null)
          older_than            = try(condition.value.olderThan, null)
          newer_than            = try(condition.value.newerThan, null)
          package_name_prefixes = try(condition.value.packageNamePrefixes, null)
        }
      }

      dynamic "most_recent_versions" {
        for_each = try([cleanup_policies.value.mostRecentVersions], [])
        content {
          keep_count            = most_recent_versions.value.keepCount
          package_name_prefixes = try(most_recent_versions.value.packageNamePrefixes, null)
        }
      }
    }
  }
}
