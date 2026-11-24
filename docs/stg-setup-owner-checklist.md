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

- [ ] サインインは Firebase Auth（Apple と Google だけ）です。自前の `MOUTHY_SESSION_SECRET` は使いません。本番（`NODE_ENV=production`）の `/api/me`、`/api/realtime/session`、`/api/feedback/judge`、`/api/feedback/review`、`/api/providers/gemini/token` は Firebase の ID トークンが必要です。`GOOGLE_CLOUD_PROJECT` が空の本番は 503 で、URL を知っていても OpenAI のトークンは発行しません。`GET /api/health` は 200 のままです。
- [ ] `MOUTHY_CLIENT_TOKEN` は STG では使いません。Xcode Cloud の変数 `MOUTHY_GOOGLE_CLIENT_ID` と `MOUTHY_GOOGLE_REVERSED_CLIENT_ID` も使いません。手元で `NODE_ENV` が `production` でないときだけ、空の `MOUTHY_CLIENT_TOKEN` なら従来どおりチェックしません。
- [ ] 以前の入れ物 `mouthy-session-secret` が残っていても、Cloud Run にはマウントしません。消すなら（任意）:

```bash
gcloud secrets delete mouthy-session-secret --project=mouthy-stg --quiet
```

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
- [ ] Identifiers に App ID **`com.mouthy.stg`** を作る。Capability は **Sign in with Apple**。Push 通知は使っていない。
- [ ] Firebase の Apple プロバイダ用に、Services ID（例: `com.mouthy.stg.signin`）を作る。Sign in with Apple を有効にし、返却 URL は `https://mouthy-stg.firebaseapp.com/__/auth/handler`。ドメインは `mouthy-stg.firebaseapp.com`。
- [ ] Keys で Sign in with Apple のキーを作り、`.p8` を一度だけダウンロードする。Key ID とチーム ID `P975GG75YV` を控える。`.p8` はリポジトリに置かない。
- [ ] Xcode のターゲット「Mouthy STG」の Signing & Capabilities に Sign in with Apple が出ていること（`ios/Mouthy.entitlements` に入っています）。
- [ ] 署名は Automatic（Xcode / Xcode Cloud が Development と Distribution の証明書とプロビジョニングプロファイルを作る）。手元に書き出した `.p12` や `.mobileprovision` はリポジトリに置かない。
- [ ] App Store Connect にアプリを作る。バンドル ID は `com.mouthy.stg`。アプリ名は **Mouthy STG**。SKU は任意（例: `mouthy-stg`）。
- [ ] Xcode Cloud をそのアプリで有効にし、リポジトリ `MasatoNagashima/mouthy` を接続する。プロダクト名は **Mouthy STG**（ターゲット「Mouthy STG」に 1 つ）。
- [ ] ワークフロー名は **Deploy Mouthy STG**。スキーム `Mouthy STG`。開始条件は `main` の iOS 変更。アクションは Archive。配布先は TestFlight の内部テスト。`ci_post_clone.sh` が `ios/MouthyLogic` の `swift test` を流す。Google のクライアント ID を Xcode Cloud の環境変数には入れない。`ios/Mouthy/GoogleService-Info.plist` がビルドに入る。
- [ ] 内部テスターの Apple ID を TestFlight に追加する。
- [ ] **App Store Connect API キー**（Issuer ID、Key ID、`.p8`）は、このリポジトリの GitHub Actions も Xcode Cloud も使いません。Xcode Cloud は Apple ID の接続でアップロードします。あとから Fastlane などで外から上げるときにだけ、GitHub Secrets の `APPSTORE_API_KEY_ID`、`APPSTORE_API_ISSUER_ID`、`APPSTORE_API_PRIVATE_KEY` に入れてください。`.p8` はコミットしない。

Cloud Run の URL が `stg-deploy` のログ（または `terraform output api_url`）に出たら:

- [ ] `ios/Config/stg/Mouthy.xcconfig` の `API_BASE_URL` をその URL にする。xcconfig は `//` をコメントとみなすので、ファイル先頭のコメントどおり `https:/$()/ホスト` と書く。
- [ ] そのコミットを main に載せて、Xcode Cloud を回す。実機は STG の API にだけ話す。

マイクの使用目的文は「AIと英語で会話するために使います。録音は保存しません。」です。暗号化は非免除ではない（`ITSAppUsesNonExemptEncryption = false`）。輸出コンプライアンスの質問では、標準の HTTPS のみ、と答えられます。プライバシーポリシーの公開 URL はまだ無く、アプリ内の文面は下書きです。審査に出す前に URL を用意してください。

サインインは Apple または Google が必須です。タブは、Firebase のサインインのあと `GET /api/me` が成功してから開きます。セッションは Firebase Auth がキーチェーンに持ちます。前回の方法は「前回のログイン」と出て、サインアウトでは消えず、アカウント削除で消えます。`GoogleService-Info.plist` が無いビルドは、サインインを「いまはこの方法でサインインできません」と出して止まります。

## 4b. Firebase（既存の GCP プロジェクト `mouthy-stg`）

別の Firebase プロジェクトは作りません。Terraform は Firebase を管理しません（Shadowly と同じ。`gha-stg-deploy` は Firebase Admin を持たない）。プロジェクトオーナーが、`mouthy-stg` にログインした状態で次を実行します。

```bash
gcloud services enable firebase.googleapis.com identitytoolkit.googleapis.com \
  --project=mouthy-stg

# 既存の GCP プロジェクトに Firebase を足す（長い操作）。
curl -sS -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "x-goog-user-project: mouthy-stg" \
  "https://firebase.googleapis.com/v1beta1/projects/mouthy-stg:addFirebase"

# Identity Platform を初期化する。
curl -sS -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "x-goog-user-project: mouthy-stg" \
  -H "Content-Type: application/json" \
  "https://identitytoolkit.googleapis.com/v2/projects/mouthy-stg/identityPlatform:initializeAuth" \
  -d '{}'

# iOS アプリ。bundleId は com.mouthy.stg、表示名は Mouthy STG。
curl -sS -X POST \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "x-goog-user-project: mouthy-stg" \
  -H "Content-Type: application/json" \
  "https://firebase.googleapis.com/v1beta1/projects/mouthy-stg/iosApps" \
  -d '{"bundleId":"com.mouthy.stg","displayName":"Mouthy STG"}'
```

返事の `name` の末尾（`1:数字:ios:...`）が APP_ID です。plist を取って、このパスにコミットします。

```bash
APP_ID='1:637092712725:ios:________'
curl -sS \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "x-goog-user-project: mouthy-stg" \
  "https://firebase.googleapis.com/v1beta1/projects/mouthy-stg/iosApps/${APP_ID}/config" \
  | python3 -c 'import json,sys,base64; print(base64.b64decode(json.load(sys.stdin)["configFileContents"]).decode())' \
  > ios/Mouthy/GoogleService-Info.plist
```

`firebase` CLI がある場合の同じ操作:

```bash
firebase projects:addfirebase mouthy-stg
firebase apps:create IOS "Mouthy STG" --bundle-id=com.mouthy.stg --project=mouthy-stg
firebase apps:sdkconfig IOS "$APP_ID" --project=mouthy-stg -o ios/Mouthy/GoogleService-Info.plist
```

Google プロバイダは、Firebase が自動で作る **ウェブ** クライアントの ID とシークレットを使います（iOS クライアントの ID ではない）。[認証情報](https://console.cloud.google.com/apis/credentials?project=mouthy-stg) の「Web client (auto created by Google Service)」から控えます。

```bash
curl -sS -X PATCH \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "x-goog-user-project: mouthy-stg" \
  -H "Content-Type: application/json" \
  "https://identitytoolkit.googleapis.com/v2/projects/mouthy-stg/defaultSupportedIdpConfigs/google.com?updateMask=enabled,clientId,clientSecret" \
  -d '{"enabled":true,"clientId":"WEB_CLIENT_ID","clientSecret":"WEB_CLIENT_SECRET"}'
```

Apple プロバイダの `.p8` はコンソールで作った鍵です。ファイルから改行を `\n` にした文字列を `PRIVATE_KEY` に入れます。

```bash
curl -sS -X PATCH \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  -H "x-goog-user-project: mouthy-stg" \
  -H "Content-Type: application/json" \
  "https://identitytoolkit.googleapis.com/v2/projects/mouthy-stg/defaultSupportedIdpConfigs/apple.com?updateMask=enabled,clientId,appleSignInConfig" \
  -d '{"enabled":true,"clientId":"com.mouthy.stg.signin","appleSignInConfig":{"codeFlowConfig":{"teamId":"P975GG75YV","keyId":"KEY_ID","privateKey":"PRIVATE_KEY"}}}'
```

メールとパスワードのプロバイダは有効にしないでください。

同意画面が未作成なら、[OAuth 同意画面](https://console.cloud.google.com/auth/overview?project=mouthy-stg) で External、アプリ名 Mouthy STG、サポートメールは本人のアドレスにします。これはコンソールだけの作業です。

## 5. 動作確認

- [ ] `openai-api-key` を入れたあと、main の `stg-deploy` が `GET /api/health` で `{"ok":true}` を確認して終わる。
- [ ] ローカルの Web デモは今までどおり `npm install && npm test && npm run dev`。待受は `127.0.0.1`。`HOST=0.0.0.0` は Cloud Run だけ。
- [ ] iOS は Xcode でスキーム `Mouthy STG` を開き、シミュレータで起動する。API が手元のサーバーなら xcconfig の `http://127.0.0.1:8787` のままでよい。シミュレータから Mac のサーバーへは、必要なら Mac の LAN アドレスに変える。

## 6. この環境では確認できていないこと

- Xcode による iOS アプリのビルド、署名、シミュレータ起動、マイクを使った実音声。
- OpenAI の短命トークンでの WebSocket 接続（鍵が無いため）。
- `terraform apply` と Cloud Run へのこの変更のデプロイ。`mouthy-session-secret` のバージョンが無いと、新しいリビジョンは起動せず `stg-deploy` が失敗します。失敗しているあいだは、認証のないいまのリビジョンが残ります。
- Xcode Cloud での署名、Google の URL scheme、Apple / Google の実ログイン。
