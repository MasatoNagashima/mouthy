#!/bin/bash
# Deploy the STG Cloud Run API (mouthy-api) from the checked-out commit.
# GitHub Actions (.github/workflows/stg-deploy.yml) runs this on main after
# terraform apply, signed in as gha-stg-deploy through Workload Identity (no key).
# The service label mouthy-commit records the deployed commit. Changed files since
# that commit decide whether to rebuild (ci/stg_deploy_plan.sh).
# Images are built by Cloud Build (server/cloudbuild.api.yaml), not on the runner.
# The gcloud flags below must match infra/envs/stg/main.tf.
# This script never targets a production project.

set -euo pipefail

project="${STG_PROJECT_ID:-mouthy-stg}"
region="${STG_REGION:-asia-northeast1}"
service="${STG_SERVICE:-mouthy-api}"
repo="${STG_DEPLOY_REPO:-$(git rev-parse --show-toplevel)}"

# shellcheck source=stg_deploy_plan.sh
source "$(dirname "${BASH_SOURCE[0]}")/stg_deploy_plan.sh"

head_commit="$(git -C "$repo" rev-parse HEAD)"

submit_build() {
  local build_id status
  build_id="$(
    gcloud builds submit \
      --project="$project" \
      --region="$region" \
      --config="server/cloudbuild.api.yaml" \
      --async \
      --format='value(id)' \
      "$repo"
  )"
  build_id="${build_id//[[:space:]]/}"
  if [[ -z "$build_id" ]]; then
    echo "Cloud Build did not return an id" >&2
    exit 1
  fi
  echo "submitted server/cloudbuild.api.yaml id=${build_id}"
  status="QUEUED"
  while [[ "$status" == "QUEUED" || "$status" == "PENDING" || "$status" == "WORKING" ]]; do
    sleep "${STG_BUILD_POLL_SECONDS:-20}"
    status="$(
      gcloud builds describe "$build_id" \
        --project="$project" \
        --region="$region" \
        --format='value(status)'
    )"
    status="${status//[[:space:]]/}"
    echo "build ${build_id} ${status}"
  done
  if [[ "$status" != "SUCCESS" ]]; then
    echo "image build failed with ${status}" >&2
    gcloud builds log "$build_id" --project="$project" --region="$region" || true
    exit 1
  fi
}

deployed_commit() {
  gcloud run services describe "$service" \
    --project="$project" \
    --region="$region" \
    --format='value(metadata.labels.mouthy-commit)' 2>/dev/null || true
}

serving_image() {
  local revision
  revision="$(
    gcloud run services describe "$service" \
      --project="$project" \
      --region="$region" \
      --format='value(status.latestReadyRevisionName)'
  )"
  gcloud run revisions describe "$revision" \
    --project="$project" \
    --region="$region" \
    --format='value(spec.containers[0].image)'
}

read -r api_build api_redeploy api_reason <<<"$(stg_plan_for "$repo" "$(deployed_commit)" "$head_commit")"
echo "plan api build=${api_build} redeploy=${api_redeploy} (${api_reason})"

if [[ "$api_build$api_redeploy" == "00" ]]; then
  echo "no STG image or deploy input changed; skip STG deploy"
  exit 0
fi

image="asia-northeast1-docker.pkg.dev/${project}/mouthy/api:stg"
if [[ "$api_build" == 1 ]]; then
  submit_build
else
  image="$(serving_image)"
fi

echo "deploy ${service} image=${image}"
gcloud run deploy "$service" \
  --project="$project" \
  --region="$region" \
  --image="$image" \
  --service-account="mouthy-api@${project}.iam.gserviceaccount.com" \
  --allow-unauthenticated \
  --ingress=all \
  --min-instances=0 \
  --max-instances=3 \
  --cpu=1 \
  --memory=512Mi \
  --timeout=300 \
  --port=8080 \
  --set-env-vars="HOST=0.0.0.0,NODE_ENV=production" \
  --set-secrets="OPENAI_API_KEY=openai-api-key:latest" \
  --update-labels="mouthy-commit=${head_commit}" \
  --quiet

api_url="$(gcloud run services describe "$service" --project="$project" --region="$region" --format='value(status.url)')"
body="$(mktemp)"
status="$(curl -sS -o "$body" -w "%{http_code}" "${api_url}/api/health")"
echo "health_status=${status}"
cat "$body"
echo
if [[ "$status" != "200" ]] || ! grep -q '"ok":true' "$body"; then
  echo "STG health check failed" >&2
  exit 1
fi
rm -f "$body"
echo "STG API ${api_url}"
