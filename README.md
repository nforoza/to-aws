# GitHub Actions → AWS OIDC integration (CloudFormation)

This folder contains CloudFormation templates to integrate GitHub Actions with AWS using OIDC. The templates create an OIDC provider, two managed IAM policies, and two IAM roles that GitHub Actions can assume.

Files
- `github_oidc_provider.yaml` — Creates an IAM OIDC provider for GitHub Actions (`token.actions.githubusercontent.com`).
- `github_policies.yaml` — Creates two IAM managed policies:
  - Infra policy (CloudFormation + S3 + PassRole)
  - App policy (Lambda deploy permissions)
- `github_roles.yaml` — Creates two IAM roles with trust configured for GitHub OIDC (branch or environment subject). Each role attaches one of the managed policies.
- `github_aws_integration.yaml` — Root stack that deploys the three child stacks and wires outputs between them.

Quick overview
- Deploy the OIDC provider so GitHub Actions can request web identity tokens AWS trusts.
- Create managed policies that describe allowed actions for infra (CloudFormation) and app (Lambda) deployments.
- Create roles that GitHub Actions can assume via OIDC; role trust is restricted to a repo+branch or repo+environment.
- Use the root stack (`github_aws_integration.yaml`) to deploy child stacks in one go (recommended) or deploy child templates individually.

Key parameters (summary)
- `github_oidc_provider.yaml`
  - `ProviderUrl` (default `https://token.actions.githubusercontent.com`)
  - `Audience` (default `sts.amazonaws.com`)
  - `ThumbprintList` (default GitHub CA thumbprint)

- `github_policies.yaml`
  - `InfraPolicyName`, `AppPolicyName` — managed policy names
  - `CloudFormationStackNamePrefix` — optional, restrict CloudFormation actions to stacks with this prefix
  - `ArtifactBucketName` — optional S3 bucket name to limit S3 access
  - `LambdaFunctionArn` — restrict Lambda actions

- `github_roles.yaml`
  - `GitHubOidcProviderArn` — ARN from the OIDC stack
  - `UseGitHubEnvironment` — `'true'` to use environment subject or `'false'` for branch subject
  - `GitHubOrg`, `GitHubRepo`, `GitHubBranch`, `GitHubEnvironmentName`
  - `InfraPolicyArn`, `AppPolicyArn` — ARNs of the managed policies

- `github_aws_integration.yaml` (root)
  - `OidcTemplateUrl`, `PoliciesTemplateUrl`, `RolesTemplateUrl` — S3 URLs for child templates
  - `GitHubConfigJson`, `RoleConfigJson` — convenience JSON strings

Important outputs
- `GitHubOidcProviderArn` — ARN of the OIDC provider
- `InfraPolicyArn` / `AppPolicyArn` — ARNs of the managed policies
- `GitHubInfraRoleArn` / `GitHubAppRoleArn` — ARNs of the roles GitHub Actions will assume

Deployment example (upload child templates to S3 and deploy root)

1) Upload templates to S3 (replace `my-cf-templates` and region/account with your values):

```zsh
aws s3 cp github_oidc_provider.yaml s3://my-cf-templates/github_oidc_provider.yaml
aws s3 cp github_policies.yaml s3://my-cf-templates/github_policies.yaml
aws s3 cp github_roles.yaml s3://my-cf-templates/github_roles.yaml
```

2) Deploy root stack (providing Template URLs):

```zsh
aws cloudformation deploy \
  --stack-name GitHub-Actions-Integration \
  --template-file github_aws_integration.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    OidcTemplateUrl=https://my-cf-templates.s3.amazonaws.com/github_oidc_provider.yaml \
    PoliciesTemplateUrl=https://my-cf-templates.s3.amazonaws.com/github_policies.yaml \
    RolesTemplateUrl=https://my-cf-templates.s3.amazonaws.com/github_roles.yaml \
  --region us-east-1
```

Notes
- `CAPABILITY_NAMED_IAM` is required because these templates create IAM resources.
- Alternatively deploy child templates individually and pass stack outputs (OIDC ARN, policy ARNs) to the roles stack.

Sample minimal parameter values (for tests)
- GitHub org: `acme`
- repo: `service`
- branch: `main`
- Use branch subject (default behaviour)

Security and best practices
- Least privilege
  - Restrict `iam:PassRole` where possible (current policy allows `role/*` — tighten it to specific roles CloudFormation should pass).
  - Restrict `LambdaFunctionArn` to only the Lambda(s) that need deploy access.
  - Use `CloudFormationStackNamePrefix` to scope CloudFormation permission to stacks created by GitHub.
- Use GitHub Environments
  - For stricter controls on production deployments, enable `UseGitHubEnvironment` and set `GitHubEnvironmentName`. Use required reviewers and approvals in GitHub.
- S3 artifact bucket
  - If you upload build artifacts to S3, set `ArtifactBucketName` to constrain S3 access, enable SSE, and restrict bucket policy.
- Validate thumbprint and provider URL
  - The default thumbprint is GitHub's common CA fingerprint; verify if your environment needs a different value.
- Session duration
  - Consider adding `MaxSessionDuration` to roles if you want to cap assumed-session length.
- Test in non-prod first
  - Deploy to a sandbox account or staging environment and test workflows before granting prod privileges.

Using the roles in GitHub Actions

- Ensure the job requests an ID token and `contents: read` when checking out code.
- Example job using `aws-actions/configure-aws-credentials` to assume the infra role:

```yaml
jobs:
  deploy-infra:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    steps:
      - name: Configure AWS credentials via OIDC
        uses: aws-actions/configure-aws-credentials@v2
        with:
          role-to-assume: arn:aws:iam::123456789012:role/github-actions-infra-role
          aws-region: us-east-1

      - name: Deploy CloudFormation
        run: |
          aws cloudformation deploy --template-file infra.yaml --stack-name acme-infra-stack
```