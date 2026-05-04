#!/usr/bin/env bash
# Uploads CloudFormation child templates to S3.
# Requires: CF_BUCKET, CF_PREFIX, AWS_REGION
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

S3="s3://${CF_BUCKET}/${CF_PREFIX}"

aws s3 cp github_sam_policies.yaml    "${S3}/github_sam_policies.yaml"
aws s3 cp github_infra_policies.yaml  "${S3}/github_infra_policies.yaml"
aws s3 cp github_app_role.yaml        "${S3}/github_app_role.yaml"
aws s3 cp github_infra_role.yaml      "${S3}/github_infra_role.yaml"
aws s3 cp github_aws_integration.yaml "${S3}/github_aws_integration.yaml"
