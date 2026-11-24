# インフラ (Terraform) と CI/CD

対象は STG（GCP プロジェクト `mouthy-stg`）だけです。本番のディレクトリ、ワークフロー、デプロイ先はありません。

## 分担

| 何を | どこで | いつ |
| --- | --- | --- |
| iOS のビルド、TestFlight | Xcode Cloud（プロダクト「Mouthy STG」、ワークフロー「Deploy Mouthy STG」） | main の iOS 変更で Archive、TestFlight 内部テスト |
| サーバーの単体テストと `ios/MouthyLogic` の Swift テスト | GitHub Actions `server-ci` | PR |
| `terraform plan`（STG） | GitHub Actions `infra-plan` | PR（`infra/` が変わったとき） |
| `terraform apply`（STG）→ Cloud Run `mouthy-api` | GitHub Actions `stg-deploy` | main への push、手動実行 |

- Actions は Linux ランナー（`ubuntu-24.04`）だけです。macOS ランナーは使いません。
- Google Cloud への認証は Workload Identity 連携（鍵なし）です。JSON の鍵は作りません。
- イメージは Cloud Build（`server/cloudbuild.api.yaml`）で作ります。ランナーでは作りません。
- Cloud Run のイメージと `mouthy-commit` ラベルは `ci/stg_deploy.sh` が差し替え、Terraform は見ません（`ignore_changes`）。CPU、メモリ、環境変数は Terraform と `ci/stg_deploy.sh` の両方に書いてあるので、変えるときは両方を変えます。

Shadowly との違い: 採点用の別サービス、Firestore、録音バケット、本番（prd）の plan / apply はありません。履歴は iOS の端末内に置きます。サーバーは短命トークン、Q&A 判定、総合点の計算です。

## ディレクトリ

```
infra/
  project.json          プロジェクト ID と番号。番号はオーナーが埋める
  bootstrap/stg/        GitHub Actions 用の認証と状態ファイル置き場。手元で一度だけ apply
  envs/stg/             STG の本体。CI が apply する
  modules/              cloud_run_service, service_account, artifact_registry
  artifact-registry/    クリーンアップポリシー
```

### Terraform が持つもの (STG)

- サービスアカウント `mouthy-api`（Secret Manager の読み取り）
- Cloud Run `mouthy-api`（公開）。起動確認は `GET /api/health`
- Artifact Registry `mouthy`
- Secret Manager `openai-api-key` の入れ物と読み取り権限（値は持たない）
- `gha-stg-plan` / `gha-stg-deploy` と Workload Identity プール（`bootstrap/stg`）

IAM は追加型（`*_iam_member`）です。ここに書いていないバインディングは消しません。

### 持たないもの

本番プロジェクト、課金と予算、秘密の値、Firebase、Apple 側の設定、監視。

## 初めて動かす手順

詳細なチェックリストは [docs/stg-setup-owner-checklist.md](../docs/stg-setup-owner-checklist.md) です。

1. GCP プロジェクト `mouthy-stg` を作り、`infra/project.json` の `project_number` を実番号にする。
2. 手元で `infra/bootstrap/stg` を apply し、出た 4 つの値を GitHub の Variables に入れる。
3. `versions.tf` の backend を有効にして `terraform init -migrate-state`。
4. Secret Manager の `openai-api-key` に鍵のバージョンを入れる（Terraform の apply より前）。
5. main へマージすると `stg-deploy` が apply とデプロイを流す。

`apply` は CI（main）だけが行います。`envs/stg` は手元から apply しません。

## 手元で plan だけ流すとき

```bash
cd infra/envs/stg
export GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token)"
terraform init
terraform plan -lock=false
```
