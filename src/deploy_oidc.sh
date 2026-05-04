#!/usr/bin/env bash
# Deploys the GitHub Actions OIDC provider — one per AWS account, shared by all repo stacks.
# Requires: AWS_REGION
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

aws cloudformation deploy \
  --stack-name  GitHub-Actions-OIDC-Provider \
  --template-file github_oidc_provider.yaml \
  --capabilities CAPABILITY_IAM \
  --no-fail-on-empty-changeset \
  --tags \
    Project="${PROJECT:-github-actions-oidc}" \
    ManagedBy="${MANAGED_BY:-cloudformation}" \
  --region "${AWS_REGION}"
