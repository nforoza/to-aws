#!/usr/bin/env bash
# Orchestrates the full deployment: uploads CloudFormation templates to S3,
# then deploys the GitHub Actions OIDC integration stack.
#
# Usage:
#   ./deploy.sh [OPTIONS]
#
# Options:
#   --github-org      <value>   GitHub organization or username (e.g. my-org)
#   --github-repo     <value>   Repository that will assume the IAM roles (e.g. my-app)
#   --github-branch   <value>   Branch allowed to assume the roles (e.g. main)
#   --cf-bucket       <value>   S3 bucket where CloudFormation templates are stored
#   --cf-prefix       <value>   S3 key prefix (folder) inside the bucket (e.g. github-integration)
#   --artifact-bucket <value>   S3 bucket name used to store Lambda deployment artifacts
#   --region          <value>   AWS region to deploy into (e.g. us-east-1)
#
# Example:
#   ./deploy.sh \
#     --github-org my-org \
#     --github-repo my-app \
#     --github-branch main \
#     --cf-bucket my-cloudformation-bucket \
#     --cf-prefix github-integration \
#     --artifact-bucket my-artifacts-bucket \
#     --region us-east-1
set -euo pipefail

usage() {
  grep '^#' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

GITHUB_ORG="${GITHUB_ORG:-}"
GITHUB_REPO="${GITHUB_REPO:-}"
GITHUB_BRANCH="${GITHUB_BRANCH:-}"
CF_BUCKET="${CF_BUCKET:-}"
CF_PREFIX="${CF_PREFIX:-}"
ARTIFACT_BUCKET="${ARTIFACT_BUCKET:-}"
AWS_REGION="${AWS_REGION:-}"

while [[ $# -gt 0 ]]; do
  case $1 in
    --github-org)      GITHUB_ORG="$2";      shift 2 ;;
    --github-repo)     GITHUB_REPO="$2";     shift 2 ;;
    --github-branch)   GITHUB_BRANCH="$2";   shift 2 ;;
    --cf-bucket)       CF_BUCKET="$2";       shift 2 ;;
    --cf-prefix)       CF_PREFIX="$2";       shift 2 ;;
    --artifact-bucket) ARTIFACT_BUCKET="$2"; shift 2 ;;
    --region)          AWS_REGION="$2";      shift 2 ;;
    --help|-h)         usage ;;
    *) echo "Error: unknown argument '$1'" >&2; usage ;;
  esac
done

# Validate all required parameters are provided
MISSING=()
[[ -z "${GITHUB_ORG}"      ]] && MISSING+=(--github-org)
[[ -z "${GITHUB_REPO}"     ]] && MISSING+=(--github-repo)
[[ -z "${GITHUB_BRANCH}"   ]] && MISSING+=(--github-branch)
[[ -z "${CF_BUCKET}"       ]] && MISSING+=(--cf-bucket)
[[ -z "${CF_PREFIX}"       ]] && MISSING+=(--cf-prefix)
[[ -z "${ARTIFACT_BUCKET}" ]] && MISSING+=(--artifact-bucket)
[[ -z "${AWS_REGION}"      ]] && MISSING+=(--region)

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "Error: missing required parameters: ${MISSING[*]}" >&2
  usage
fi

export GITHUB_ORG GITHUB_REPO GITHUB_BRANCH CF_BUCKET CF_PREFIX ARTIFACT_BUCKET AWS_REGION

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${SCRIPT_DIR}/upload_templates.sh"
"${SCRIPT_DIR}/cloudformation.sh"
