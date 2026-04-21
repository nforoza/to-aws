#!/usr/bin/env bash
# Deploys the GitHub Actions OIDC integration CloudFormation stack.
# Creates two IAM roles (infra and app) that the specified GitHub repository
# can assume via OIDC — no long-lived AWS credentials needed in GitHub.
#
# Expected environment variables (set by deploy.sh or exported manually):
#   GITHUB_ORG      GitHub organization or username
#   GITHUB_REPO     Repository that will assume the IAM roles
#   GITHUB_BRANCH   Branch allowed to assume the roles
#   CF_BUCKET       S3 bucket where CloudFormation templates are stored
#   CF_PREFIX       S3 key prefix (folder) inside the bucket
#   ARTIFACT_BUCKET S3 bucket name used to store Lambda deployment artifacts
#   AWS_REGION      AWS region to deploy into
set -euo pipefail

# Exhaustive list of current AWS regions. Used to catch typos before making
# any AWS API calls. Update this list when AWS adds new regions.
VALID_REGIONS="us-east-1 us-east-2 us-west-1 us-west-2 \
  ca-central-1 ca-west-1 \
  eu-west-1 eu-west-2 eu-west-3 eu-central-1 eu-central-2 eu-north-1 eu-south-1 eu-south-2 \
  ap-east-1 ap-south-1 ap-south-2 ap-southeast-1 ap-southeast-2 ap-southeast-3 ap-southeast-4 ap-northeast-1 ap-northeast-2 ap-northeast-3 \
  sa-east-1 me-south-1 me-central-1 af-south-1 il-central-1"

if ! echo "${VALID_REGIONS}" | grep -qw "${AWS_REGION}"; then
  echo "Error: '${AWS_REGION}' is not a valid AWS region." >&2
  exit 1
fi

# Build the HTTPS base URL from bucket + prefix so both upload_templates.sh
# and this script share the same source of truth for the S3 location.
TEMPLATES_BASE_URL="https://${CF_BUCKET}.s3.${AWS_REGION}.amazonaws.com/${CF_PREFIX}"

# Role names include the repo name so multiple stacks can be deployed side by
# side without IAM name collisions (e.g. one per repository).
aws cloudformation deploy \
  --stack-name "GitHub-Actions-Integration-${GITHUB_REPO}" \
  --template-file github_aws_integration.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    OidcTemplateUrl="${TEMPLATES_BASE_URL}/github_oidc_provider.yaml" \
    PoliciesTemplateUrl="${TEMPLATES_BASE_URL}/github_policies.yaml" \
    RolesTemplateUrl="${TEMPLATES_BASE_URL}/github_roles.yaml" \
    GitHubOrg="${GITHUB_ORG}" \
    GitHubRepo="${GITHUB_REPO}" \
    GitHubBranch="${GITHUB_BRANCH}" \
    ArtifactBucketName="${ARTIFACT_BUCKET}" \
    InfraRoleName="github-infra-${GITHUB_REPO}" \
    AppRoleName="github-app-${GITHUB_REPO}" \
    CloudFormationStackNamePrefix="${STACK_PREFIX}" \
    CloudFormationExecutionRolePrefix="${CFN_ROLE_PREFIX}" \
  --region "${AWS_REGION}"
