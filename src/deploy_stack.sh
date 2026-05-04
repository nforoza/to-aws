#!/usr/bin/env bash
# Deploys one GitHub Actions integration stack (one policy + one role for one repository).
# Requires: GITHUB_ORG, GITHUB_REPO, GITHUB_BRANCH, CF_BUCKET, CF_PREFIX,
#           ARTIFACT_BUCKET, AWS_REGION, STACK_PREFIX, CFN_ROLE_PREFIX,
#           POLICY_TYPE, OIDC_PROVIDER_ARN
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

BASE_URL="https://${CF_BUCKET}.s3.${AWS_REGION}.amazonaws.com/${CF_PREFIX}"

case "${POLICY_TYPE}" in
  sam)
    POLICIES_URL="${BASE_URL}/github_sam_policies.yaml"
    ROLE_URL="${BASE_URL}/github_app_role.yaml"
    ROLE_NAME="github-app-${GITHUB_REPO}"
    ;;
  infra)
    POLICIES_URL="${BASE_URL}/github_infra_policies.yaml"
    ROLE_URL="${BASE_URL}/github_infra_role.yaml"
    ROLE_NAME="github-infra-${GITHUB_REPO}"
    ;;
  *)
    echo "Error: POLICY_TYPE must be 'sam' or 'infra', got '${POLICY_TYPE}'" >&2
    exit 1
    ;;
esac

aws cloudformation deploy \
  --stack-name "GitHub-Actions-Integration-${GITHUB_REPO}" \
  --template-file github_aws_integration.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --no-fail-on-empty-changeset \
  --tags \
    Application="${APPLICATION}" \
    Project="${PROJECT:-github-actions-oidc}" \
    GitHubOrg="${GITHUB_ORG}" \
    GitHubRepo="${GITHUB_REPO}" \
    DeploymentType="${POLICY_TYPE}" \
    ManagedBy="${MANAGED_BY:-cloudformation}" \
  --parameter-overrides \
    OidcProviderArn="${OIDC_PROVIDER_ARN}" \
    PoliciesTemplateUrl="${POLICIES_URL}" \
    RoleTemplateUrl="${ROLE_URL}" \
    GitHubOrg="${GITHUB_ORG}" \
    GitHubRepo="${GITHUB_REPO}" \
    GitHubBranch="${GITHUB_BRANCH}" \
    ArtifactBucketName="${ARTIFACT_BUCKET}" \
    RoleName="${ROLE_NAME}" \
    PolicyName="github-actions-policy-${GITHUB_REPO}" \
    CloudFormationStackNamePrefix="${STACK_PREFIX}" \
    CloudFormationExecutionRolePrefix="${CFN_ROLE_PREFIX}" \
    Application="${APPLICATION}" \
    Project="${PROJECT:-github-actions-oidc}" \
    DeploymentType="${POLICY_TYPE}" \
    ManagedBy="${MANAGED_BY:-cloudformation}" \
  --region "${AWS_REGION}"
