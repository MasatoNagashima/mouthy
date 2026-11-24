# STG セットアップ：オーナーがやること

対象は Google Cloud の **STG（`mouthy-stg`）だけ** です。本番プロジェクトは作らず、このリポジトリにも本番の Terraform とデプロイはありません。OpenAI の API キーは、あとからこのチェックリストの場所に入れてください。リポジトリやアプリには書かないでください。

Shadowly（`MasatoNagashima/shadowly`）と同じ形です。GitHub Actions は Linux だけ、認証は Workload Identity 連携（JSON 鍵なし）、iOS のビルドと TestFlight は Xcode Cloud です。

## 1. Google Cloud（STG プロジェクト）

- [ ] 請求先アカウントに紐づく GCP プロジェクトを **`mouthy-stg`** という ID で作る。リージョンは `asia-northeast1`。
- [ ] 本番用のプロジェクトは作らない。`mouthy-prd` や Shadowly の `shadowly-prd` には、この作業で権限を足さない。
- [ ] `gcloud projects describe mouthy-stg --format='value(projectNumber)'` の番号を、`infra/project.json` の `project_number`（いまは `"0"`）に書いてコミットする。`"0"` のままだと、Cloud Build の既定サービスアカウントへの `actAs` は作られない。
- [ ] 手元の apply に使う Google アカウントへ、`mouthy-stg` の **Owner**（または Editor + Service Usage Admin + IAM 管理者 + Storage Admin）を付ける。このアカウントは CI では使わない。
- [ ] 次を手元で一度だけ実行する。

```bash
cd infra/bootstrap/stg
terraform init
terraform plan
terraform apply
terraform output github_variables
```

- [ ] `infra/bootstrap/stg/versions.tf` の `backend "gcs"` のコメントを外し、`terraform init -migrate-state` で状態を `gs://mouthy-stg-tfstate` に移す。
- [ ] 作られるもの: 状態バケット `mouthy-stg-tfstate`、Workload Identity プール `github` / プロバイダ `github-actions`、サービスアカウント `gha-stg-plan`（読み取り）と `gha-stg-deploy`（main だけ）。プールは `MasatoNagashima/mouthy`（repository id `1436608181`、owner id `73416540`）のトークンしか受け付けない。
- [ ] `envs/stg` の apply は手元ではしない。main の `stg-deploy` が行う。

## 2. 秘密情報（Secret Manager）

値そのものは Terraform に書かない。入れ物だけが `infra/envs/stg` で作られる。

| 名前 | プロジェクト | どこで読むか | 中身 |
| --- | --- | --- | --- |
| `openai-api-key` | `mouthy-stg`（`asia-northeast1` のレプリカ） | Cloud Run `mouthy-api` の環境変数 `OPENAI_API_KEY`（バージョン `latest`） | OpenAI の秘密鍵（`sk-`）。ブラウザにもアプリのバイナリにも置かない |

- [ ] 最初の `stg-deploy` の **前** に、バージョンを 1 つ入れる。バージョンが無いと Cloud Run のリビジョンは起動しない。

```bash
printf '%s' 'sk-...' | gcloud secrets versions add openai-api-key \
  --project=mouthy-stg --data-file=-
```

- [ ] `MOUTHY_CLIENT_TOKEN` はいま無効（空）です。STG の `/api/realtime/session` と `/api/feedback/review` は、URL を知っていれば呼べます。短命トークンの発行で OpenAI の利用料がかかるので、公開前に次を足してください。サーバーは環境変数 `MOUTHY_CLIENT_TOKEN` が入っているときだけ、ヘッダ `X-Mouthy-Client` を要求します。
  - Secret Manager に `mouthy-client-token` を作り、Cloud Run の環境変数 `MOUTHY_CLIENT_TOKEN` に `latest` をマウントする（`infra/envs/stg/main.tf` の `env` と `ci/stg_deploy.sh` の `--set-secrets` の両方）。
  - 同じ値を Xcode Cloud の環境変数 `MOUTHY_CLIENT_TOKEN` に入れる。`ios/Config/stg/Mouthy.xcconfig` が Info.plist の `MouthyClientToken` に渡す。アプリのソースには書かない。

`GEMINI_API_KEY` は STG では使いません。ローカルの `.env` だけです。

## 3. GitHub（`MasatoNagashima/mouthy`）

Variables（Settings → Secrets and variables → Actions → **Variables**。秘密ではないので Secrets ではない）:

| 変数 | 値 |
| --- | --- |
| `GCP_STG_PROJECT_ID` | `mouthy-stg` |
| `GCP_STG_WIF_PROVIDER` | `terraform output github_variables` の `GCP_STG_WIF_PROVIDER` |
| `GCP_STG_PLAN_SA` | 同じ出力の `GCP_STG_PLAN_SA`（`gha-stg-plan@mouthy-stg.iam.gserviceaccount.com`） |
| `GCP_STG_DEPLOY_SA` | 同じ出力の `GCP_STG_DEPLOY_SA` |

- [ ] この 4 つを入れるまで、`infra-plan` の plan と `stg-deploy` は何もしない（ワークフローは成功でスキップする）。
- `gha-stg-plan` は状態バケットを読むだけです。`infra-plan` は `default.tfstate` をコピーし、ロックファイルは作りません。
- [ ] GitHub Actions の Secrets に OpenAI の鍵は置かない。JSON のサービスアカウント鍵も作らない。
- [ ] `GCP_PRD_*` や `PRD_APPSTORE_*` は Shadowly にはあるが、Mouthy には作らない。

## 4. Apple Developer と TestFlight

Xcode プロジェクトはスキーム **Mouthy STG** の 1 つだけです。バンドル ID は `com.mouthy.stg`。`DEVELOPMENT_TEAM` は Shadowly の公開プロジェクトと同じ `P975GG75YV` を仮に入れてあります。

- [ ] [developer.apple.com](https://developer.apple.com) でチーム ID が `P975GG75YV` でなければ、`ios/Mouthy.xcodeproj/project.pbxproj` の `DEVELOPMENT_TEAM` を差し替える。
- [ ] Identifiers に App ID **`com.mouthy.stg`** を作る。Capability は **Sign in with Apple**。Push 通知は使っていない。
- [ ] 署名は Automatic（Xcode / Xcode Cloud が Development と Distribution の証明書とプロビジョニングプロファイルを作る）。手元に書き出した `.p12` や `.mobileprovision` はリポジトリに置かない。
- [ ] App Store Connect にアプリを作る。バンドル ID は `com.mouthy.stg`。名前は Mouthy。SKU は任意（例: `mouthy-stg`）。
- [ ] Xcode Cloud をそのアプリで有効にし、リポジトリ `MasatoNagashima/mouthy` を接続する。
- [ ] ワークフロー: スキーム `Mouthy STG`、開始条件は `main` への変更、アクションは Archive、配布先は TestFlight の内部テスト。環境変数 `API_BASE_URL` が必要になったら、xcconfig を変える（次項）。`ci_post_clone.sh` が `ios/MouthyLogic` の `swift test` を流す。
- [ ] 内部テスターの Apple ID を TestFlight に追加する。
- [ ] **App Store Connect API キー**（Issuer ID、Key ID、`.p8`）は、このリポジトリの GitHub Actions も Xcode Cloud も使いません。Xcode Cloud は Apple ID の接続でアップロードします。あとから Fastlane などで外から上げるときにだけ、GitHub Secrets の `APPSTORE_API_KEY_ID`、`APPSTORE_API_ISSUER_ID`、`APPSTORE_API_PRIVATE_KEY` に入れてください。`.p8` はコミットしない。

Cloud Run の URL が `stg-deploy` のログ（または `terraform output api_url`）に出たら:

- [ ] `ios/Config/stg/Mouthy.xcconfig` の `API_BASE_URL` をその URL にする。xcconfig は `//` をコメントとみなすので、ファイル先頭のコメントどおり `https:/$()/ホスト` と書く。
- [ ] そのコミットを main に載せて、Xcode Cloud を回す。実機は STG の API にだけ話す。

マイクの使用目的文は「AIと英語で会話するために使います。録音は保存しません。」です。暗号化は非免除ではない（`ITSAppUsesNonExemptEncryption = false`）。輸出コンプライアンスの質問では、標準の HTTPS のみ、と答えられます。プライバシーポリシーの公開 URL はまだ無く、アプリ内の文面は下書きです。審査に出す前に URL を用意してください。

Sign in with Apple の identity token は、まだサーバーで検証していません。ユーザー ID と名前は端末内にだけ残します。アカウント削除も端末内の記録を消すだけです。

## 5. 動作確認

- [ ] `openai-api-key` を入れたあと、main の `stg-deploy` が `GET /api/health` で `{"ok":true}` を確認して終わる。
- [ ] ローカルの Web デモは今までどおり `npm install && npm test && npm run dev`。待受は `127.0.0.1`。`HOST=0.0.0.0` は Cloud Run だけ。
- [ ] iOS は Xcode でスキーム `Mouthy STG` を開き、シミュレータで起動する。API が手元のサーバーなら xcconfig の `http://127.0.0.1:8787` のままでよい。シミュレータから Mac のサーバーへは、必要なら Mac の LAN アドレスに変える。

## 6. この環境では確認できていないこと

- Xcode による iOS アプリのビルド、署名、シミュレータ起動、マイクを使った実音声。
- OpenAI の短命トークンでの WebSocket 接続（鍵が無いため）。
- `terraform apply` と Cloud Run への実際のデプロイ（`mouthy-stg` がまだ無いため）。`terraform validate` と `terraform fmt` は確認済み。
