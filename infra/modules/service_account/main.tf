# 実行用サービスアカウントと、プロジェクトに付けるロール。
# ロールは google_project_iam_member (追加型) で付けるので、ここに書いていない
# メンバーやロールを消すことはない。

resource "google_service_account" "this" {
  project      = var.project_id
  account_id   = var.account_id
  display_name = var.display_name
  description  = var.description
}

resource "google_project_iam_member" "roles" {
  for_each = toset(var.project_roles)

  project = var.project_id
  role    = each.value
  member  = google_service_account.this.member
}
