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

- [ ] セッション署名の秘密 `mouthy-session-secret` の入れ物は Terraform が作ります。**バージョンは自動では入りません。** 次の `stg-deploy` は、バージョンが無いと Cloud Run の新しいリビジョンを起動できず失敗します。その間、いま動いているリビジョン（認証なし）が残ります。マージの前か直後に、`mouthy-stg` にログインした状態で次を実行してください。

```bash
openssl rand -base64 32 | gcloud secrets versions add mouthy-session-secret \
  --project=mouthy-stg --data-file=-
```

入れ物がまだ無い（最初の apply の前）なら、先に入れ物を作ります。

```bash
gcloud secrets create mouthy-session-secret \
  --project=mouthy-stg \
  --replication-policy=user-managed \
  --locations=asia-northeast1
```

この秘密が入ると、`/api/realtime/session`、`/api/feedback/judge`、`/api/feedback/review`、`/api/providers/gemini/token` は `Authorization: Bearer` のセッショントークンが必要です。`MOUTHY_CLIENT_TOKEN` は見ません。秘密が空の本番（`NODE_ENV=production`）では、これらの経路は 503 で、URL を知っていても OpenAI のトークンは発行しません。`GET /api/health` は 200 のままです。

- [ ] `MOUTHY_CLIENT_TOKEN` は STG では使いません。Xcode Cloud にも Secret Manager にも足さないでください。手元の開発で `MOUTHY_SESSION_SECRET` が空、かつ `NODE_ENV` が `production` でないときだけ、従来の `X-Mouthy-Client` が残ります。

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

Xcode プロジェクトのターゲットとスキームは **Mouthy STG** の 1 つだけです。本番ターゲットはありません。表示名（`PRODUCT_NAME` と `CFBundleDisplayName`）も **Mouthy STG** で、ビルド成果物は `Mouthy STG.app` です。Swift モジュール名（`PRODUCT_MODULE_NAME`）は `Mouthy` のままです。バンドル ID は `com.mouthy.stg`。`DEVELOPMENT_TEAM` は Shadowly の公開プロジェクトと同じ `P975GG75YV` を仮に入れてあります。

- [ ] [developer.apple.com](https://developer.apple.com) でチーム ID が `P975GG75YV` でなければ、`ios/Mouthy.xcodeproj/project.pbxproj` の `DEVELOPMENT_TEAM` を差し替える。
- [ ] Identifiers に App ID **`com.mouthy.stg`** を作る。Capability は **Sign in with Apple**（Primary App ID はこの App ID 自体。ネイティブの Sign in with Apple に Services ID は要りません）。Push 通知は使っていない。
- [ ] Xcode のターゲット「Mouthy STG」の Signing & Capabilities に Sign in with Apple が出ていること（`ios/Mouthy.entitlements` に入っています）。App ID 側で Capability を有効にしたあと、Xcode Cloud の署名を一度通してください。
- [ ] 署名は Automatic（Xcode / Xcode Cloud が Development と Distribution の証明書とプロビジョニングプロファイルを作る）。手元に書き出した `.p12` や `.mobileprovision` はリポジトリに置かない。
- [ ] App Store Connect にアプリを作る。バンドル ID は `com.mouthy.stg`。アプリ名は **Mouthy STG**。SKU は任意（例: `mouthy-stg`）。
- [ ] Xcode Cloud をそのアプリで有効にし、リポジトリ `MasatoNagashima/mouthy` を接続する。プロダクト名は **Mouthy STG**（ターゲット「Mouthy STG」に 1 つ）。
- [ ] ワークフロー名は **Deploy Mouthy STG**。スキーム `Mouthy STG`。開始条件は `main` の iOS 変更。アクションは Archive。配布先は TestFlight の内部テスト。`ci_post_clone.sh` が `ios/MouthyLogic` の `swift test` を流す。
- [ ] そのワークフローの環境変数（Xcode Cloud → ワークフロー → Environment）に、値をリポジトリへ書かずに次の 2 つを入れる。名前はこのとおり。

| 名前 | 値 |
| --- | --- |
| `MOUTHY_GOOGLE_CLIENT_ID` | Google Cloud Console で作った iOS クライアント ID（`....apps.googleusercontent.com`） |
| `MOUTHY_GOOGLE_REVERSED_CLIENT_ID` | その ID の逆引き。`123-abc.apps.googleusercontent.com` なら `com.googleusercontent.apps.123-abc` |

`ios/Config/stg/Mouthy.xcconfig` がこの 2 つを `GID_CLIENT_ID` と `GOOGLE_REVERSED_CLIENT_ID` に渡し、Info.plist の `GIDClientID` / `GoogleReversedClientID` になります。ビルドフェーズ `ios/ci_scripts/embed_google_url_scheme.sh` が逆引き ID を URL scheme に書きます。空のあいだは URL scheme を埋め込まず、Google ボタンは「いまは Google でサインインできません」と出します。Apple はこの変数なしで動きます。
- [ ] 内部テスターの Apple ID を TestFlight に追加する。
- [ ] **App Store Connect API キー**（Issuer ID、Key ID、`.p8`）は、このリポジトリの GitHub Actions も Xcode Cloud も使いません。Xcode Cloud は Apple ID の接続でアップロードします。あとから Fastlane などで外から上げるときにだけ、GitHub Secrets の `APPSTORE_API_KEY_ID`、`APPSTORE_API_ISSUER_ID`、`APPSTORE_API_PRIVATE_KEY` に入れてください。`.p8` はコミットしない。

Cloud Run の URL が `stg-deploy` のログ（または `terraform output api_url`）に出たら:

- [ ] `ios/Config/stg/Mouthy.xcconfig` の `API_BASE_URL` をその URL にする。xcconfig は `//` をコメントとみなすので、ファイル先頭のコメントどおり `https:/$()/ホスト` と書く。
- [ ] そのコミットを main に載せて、Xcode Cloud を回す。実機は STG の API にだけ話す。

マイクの使用目的文は「AIと英語で会話するために使います。録音は保存しません。」です。暗号化は非免除ではない（`ITSAppUsesNonExemptEncryption = false`）。輸出コンプライアンスの質問では、標準の HTTPS のみ、と答えられます。プライバシーポリシーの公開 URL はまだ無く、アプリ内の文面は下書きです。審査に出す前に URL を用意してください。

サインインは Apple または Google が必須です。タブ（ホーム、シーン、記録、プロフィール）はサインインのあとだけ開きます。セッションはアプリが発行する JWT で、キーチェーン（`com.mouthy.stg`）に 30 日残します。前回の方法は「前回のログイン」と出て、サインアウトでは消えず、アカウント削除で消えます。

## 4b. Google ログイン（`mouthy-stg` の iOS クライアント）

秘密ではありません。クライアント ID は Xcode Cloud の変数と、サーバー用に `infra/google-client.json` の `iosClientId` へ入れます。JSON を空のままにすると Google のサインインは 503 です。

- [ ] [認証情報](https://console.cloud.google.com/apis/credentials?project=mouthy-stg) を開く（プロジェクトは **mouthy-stg**）。
- [ ] 「認証情報を作成」→「OAuth クライアント ID」。同意画面が未作成なら先に作ります。User Type は External、アプリ名は Mouthy STG、サポートメールは本人のアドレス。スコープは追加しない（openid / email / profile は Google ログインの既定）。
- [ ] アプリケーションの種類は **iOS**。名前は `Mouthy STG`。バンドル ID は **`com.mouthy.stg`**。App Store ID と Team ID は空でよい（Team ID を入れるなら `P975GG75YV`）。
- [ ] 作成後のクライアント ID を、上の Xcode Cloud 変数 `MOUTHY_GOOGLE_CLIENT_ID` と `infra/google-client.json` の `iosClientId` に同じ文字列で入れる。逆引き ID はコンソールの「iOS URL スキーム」に出ます。それを `MOUTHY_GOOGLE_REVERSED_CLIENT_ID` に入れる。
- [ ] クライアントシークレットは iOS クライアントには出ません。作らないでください。

Apple の ID トークンは `https://appleid.apple.com/auth/keys` で検証し、audience は `com.mouthy.stg` です。Google は `https://www.googleapis.com/oauth2/v3/certs` で、audience は iOS クライアント ID です。

## 5. 動作確認

- [ ] `openai-api-key` を入れたあと、main の `stg-deploy` が `GET /api/health` で `{"ok":true}` を確認して終わる。
- [ ] ローカルの Web デモは今までどおり `npm install && npm test && npm run dev`。待受は `127.0.0.1`。`HOST=0.0.0.0` は Cloud Run だけ。
- [ ] iOS は Xcode でスキーム `Mouthy STG` を開き、シミュレータで起動する。API が手元のサーバーなら xcconfig の `http://127.0.0.1:8787` のままでよい。シミュレータから Mac のサーバーへは、必要なら Mac の LAN アドレスに変える。

## 6. この環境では確認できていないこと

- Xcode による iOS アプリのビルド、署名、シミュレータ起動、マイクを使った実音声。
- OpenAI の短命トークンでの WebSocket 接続（鍵が無いため）。
- `terraform apply` と Cloud Run へのこの変更のデプロイ。`mouthy-session-secret` のバージョンが無いと、新しいリビジョンは起動せず `stg-deploy` が失敗します。失敗しているあいだは、認証のないいまのリビジョンが残ります。
- Xcode Cloud での署名、Google の URL scheme、Apple / Google の実ログイン。
