#!/usr/bin/env bash
# Uploads all CloudFormation child templates to S3 so they can be referenced
# as nested stack URLs during deployment.
#
# Expected environment variables (set by deploy.sh or exported manually):
#   CF_BUCKET   S3 bucket where templates will be stored
#   CF_PREFIX   S3 key prefix (folder) inside the bucket
#
# aws s3 cp overwrites existing objects by default — no extra flag needed.
set -euo pipefail

S3_TEMPLATES_PATH="s3://${CF_BUCKET}/${CF_PREFIX}"

aws s3 cp github_oidc_provider.yaml    "${S3_TEMPLATES_PATH}/github_oidc_provider.yaml"
aws s3 cp github_policies.yaml         "${S3_TEMPLATES_PATH}/github_policies.yaml"
aws s3 cp github_roles.yaml            "${S3_TEMPLATES_PATH}/github_roles.yaml"
aws s3 cp github_aws_integration.yaml  "${S3_TEMPLATES_PATH}/github_aws_integration.yaml"
