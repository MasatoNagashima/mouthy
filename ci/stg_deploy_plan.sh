#!/bin/bash
# Decide whether the STG API image must be rebuilt from the files changed since
# the commit Cloud Run last deployed. ci/stg_deploy.sh sources this file.
# The server tests run it directly: paths on stdin, "build=<0|1> redeploy=<0|1>" on stdout.
#
# The image build context is the repository root (server/Dockerfile copies the
# web demo and the token server). iOS, docs, and infra do not change the image.
# ci/stg_deploy.sh changes Cloud Run flags, so it redeploys the current image.

stg_classify_paths() {
  local build=0 redeploy=0 path
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    case "$path" in
      test/*|ios/*|infra/*|docs/*|.github/*) ;;
      ci/stg_deploy.sh|ci/stg_deploy_plan.sh) redeploy=1 ;;
      src/*|server/*|package.json|package-lock.json|tsconfig.json|vite.config.ts|index.html|.dockerignore|.gcloudignore) build=1 ;;
      *) ;;
    esac
  done
  echo "build=$build redeploy=$redeploy"
}

# stg_plan_for <repo> <base commit or empty> <head commit>
# Prints "<build 0|1> <redeploy 0|1> <reason>".
stg_plan_for() {
  local repo="$1" base="$2" head="$3" remote changed plan
  if [[ -z "$base" ]]; then
    echo "1 0 no-deployed-commit"
    return
  fi
  if [[ "$base" == "$head" ]]; then
    echo "0 0 already-deployed"
    return
  fi
  if ! git -C "$repo" cat-file -e "${base}^{commit}" 2>/dev/null; then
    remote="$(git -C "$repo" remote | head -n 1)"
    if [[ -z "$remote" ]] || ! git -C "$repo" fetch --quiet --depth=1 "$remote" "$base" 2>/dev/null; then
      echo "1 0 base-unreachable"
      return
    fi
  fi
  if ! changed="$(git -C "$repo" diff --name-only "$base" "$head" 2>/dev/null)"; then
    echo "1 0 diff-failed"
    return
  fi
  plan="$(printf '%s\n' "$changed" | stg_classify_paths)"
  local build redeploy
  build="$(sed -E 's/.*build=([01]).*/\1/' <<<"$plan")"
  redeploy="$(sed -E 's/.*redeploy=([01]).*/\1/' <<<"$plan")"
  echo "$build $redeploy diff:${plan}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  stg_classify_paths
fi
