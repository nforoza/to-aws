# GitHub Actions → AWS OIDC integration (CloudFormation)

Reusable CloudFormation templates that allow GitHub Actions workflows to authenticate with AWS via OIDC — no long-lived credentials stored in GitHub.

Deploy one stack per repository that needs AWS access. Each stack creates a scoped OIDC provider, two IAM policies, and two IAM roles that only that repository's workflows can assume.

---

## How it works

1. GitHub Actions requests a short-lived OIDC token from GitHub.
2. AWS IAM verifies the token against the OIDC provider created by these templates.
3. The workflow assumes an IAM role scoped to a specific org/repo/branch — no AWS credentials are stored anywhere.

---

## Repository structure

```
src/
├── github_aws_integration.yaml   # Root stack — deploys the three child stacks
├── github_oidc_provider.yaml     # Child stack — IAM OIDC provider for GitHub Actions
├── github_policies.yaml          # Child stack — IAM managed policies (infra + app)
├── github_roles.yaml             # Child stack — IAM roles GitHub Actions will assume
├── deploy.sh                     # Orchestrator: uploads templates then deploys the stack
├── upload_templates.sh           # Uploads CloudFormation templates to S3
└── cloudformation.sh             # Deploys the root CloudFormation stack
```

> `set_env.sh` is gitignored. Copy the template below, fill in your values, and source it before deploying.

---

## Quickstart

### 1. Create your local environment file

Create `src/set_env.sh` (it will not be committed):

```bash
#!/usr/bin/env bash
export GITHUB_ORG=<your-github-org-or-username>
export GITHUB_REPO=<repository-that-needs-aws-access>
export GITHUB_BRANCH=main
export CF_BUCKET=<s3-bucket-for-cloudformation-templates>
export CF_PREFIX=<s3-key-prefix>
export ARTIFACT_BUCKET=<s3-bucket-for-deployment-artifacts>
export AWS_REGION=<aws-region>
export STACK_PREFIX=<your-app->        # e.g. data-collector-  (scopes CloudFormation + IAM)
export CFN_ROLE_PREFIX=<role-prefix>   # e.g. github-cfn-execution-  (scopes iam:PassRole)
```

### 2. Deploy

```bash
source ./src/set_env.sh && ./src/deploy.sh
```

`deploy.sh` first uploads the CloudFormation templates to S3, then deploys the root stack.

### 3. Use flags instead of environment variables (optional)

All parameters can also be passed directly as flags, which override any exported env vars:

```bash
./src/deploy.sh \
  --github-org      my-org \
  --github-repo     my-app \
  --github-branch   main \
  --cf-bucket       my-cloudformation-bucket \
  --cf-prefix       github-integration \
  --artifact-bucket my-artifacts-bucket \
  --region          us-east-1 \
  --stack-prefix    my-app- \
  --cfn-role-prefix github-cfn-execution-
```

Run `./src/deploy.sh --help` to see all available options.

---

## Deploying for multiple repositories

Each repository that needs AWS access gets its own stack. Re-run `deploy.sh` with a different `--github-repo` value:

```bash
./src/deploy.sh --github-repo data-collector   --stack-prefix data-collector-   ...
./src/deploy.sh --github-repo another-service  --stack-prefix another-service-  ...
```

The stack name and IAM role names include the repository name to avoid conflicts:
- Stack: `GitHub-Actions-Integration-<repo>`
- Roles: `github-infra-<repo>`, `github-app-<repo>`

---

## Parameters reference

### Root stack (`github_aws_integration.yaml`)

| Parameter | Required | Description |
|---|---|---|
| `OidcTemplateUrl` | Yes | S3 HTTPS URL of `github_oidc_provider.yaml` |
| `PoliciesTemplateUrl` | Yes | S3 HTTPS URL of `github_policies.yaml` |
| `RolesTemplateUrl` | Yes | S3 HTTPS URL of `github_roles.yaml` |
| `GitHubOrg` | Yes | GitHub organization or username |
| `GitHubRepo` | Yes | Repository that will assume the roles |
| `GitHubBranch` | Yes | Branch allowed to assume the roles |
| `InfraRoleName` | Yes | IAM role name for infrastructure deployments |
| `AppRoleName` | Yes | IAM role name for Lambda application deployments |
| `ArtifactBucketName` | No | S3 bucket name (not ARN) for deployment artifacts |
| `CloudFormationStackNamePrefix` | Yes | Scopes CloudFormation actions and SAM-created IAM roles to stacks with this prefix |
| `CloudFormationExecutionRolePrefix` | Yes | Scopes `iam:PassRole` to roles whose names start with this prefix |

### Policies stack (`github_policies.yaml`)

| Parameter | Required | Description |
|---|---|---|
| `InfraPolicyName` | No | Managed policy name for infra deployments |
| `AppPolicyName` | No | Managed policy name for Lambda deployments |
| `CloudFormationStackNamePrefix` | Yes | Restricts CloudFormation and IAM role CRUD to this stack name prefix |
| `CloudFormationExecutionRolePrefix` | Yes | Restricts `iam:PassRole` to roles matching this prefix |
| `LambdaFunctionArn` | No | Lambda ARN to restrict app deploy permissions (default `*`) |
| `ArtifactBucketName` | No | S3 bucket name to constrain artifact access |

### Roles stack (`github_roles.yaml`)

| Parameter | Required | Description |
|---|---|---|
| `GitHubOrg` / `GitHubRepo` / `GitHubBranch` | Yes | OIDC trust condition — only this repo/branch can assume the roles |
| `UseGitHubEnvironment` | No | `'true'` to use a GitHub environment subject instead of a branch |
| `GitHubEnvironmentName` | No | GitHub environment name when `UseGitHubEnvironment` is `'true'` |
| `InfraRoleName` / `AppRoleName` | Yes | IAM role names |
| `InfraPolicyArn` / `AppPolicyArn` | Yes | Passed automatically by the root stack |

---

## Stack outputs

| Output | Description |
|---|---|
| `GitHubOidcProviderArn` | ARN of the OIDC provider |
| `GitHubInfraRoleArn` | ARN of the infrastructure deployment role |
| `GitHubAppRoleArn` | ARN of the Lambda application deployment role |

---

## Using the roles in GitHub Actions

Add `id-token: write` permission to the job so it can request an OIDC token, then use `aws-actions/configure-aws-credentials` to assume the role.

**SAM application deployment (infra role):**

```yaml
jobs:
  deploy-sam:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/setup-sam@v2

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::<account-id>:role/github-infra-<repo>
          aws-region: us-east-1

      - name: Build
        run: sam build

      - name: Deploy
        run: sam deploy --no-confirm-changeset --no-fail-on-empty-changeset
```

**CloudFormation-only deployment (infra role):**

```yaml
jobs:
  deploy-infra:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::<account-id>:role/github-infra-<repo>
          aws-region: us-east-1

      - name: Deploy stack
        run: aws cloudformation deploy --template-file infra.yaml --stack-name my-stack
```

**Lambda direct deployment (app role):**

```yaml
jobs:
  deploy-app:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::<account-id>:role/github-app-<repo>
          aws-region: us-east-1

      - name: Deploy Lambda
        run: aws lambda update-function-code --function-name my-function --zip-file fileb://function.zip
```

---

## Two-role model

| Role | Use case | Key permissions |
|---|---|---|
| `github-infra-<repo>` | SAM deploys, CloudFormation stacks | CloudFormation CRUD, Lambda full lifecycle, IAM role management, API Gateway, EventBridge, S3 read/write |
| `github-app-<repo>` | Direct Lambda code/config updates | Lambda update/publish only, S3 read |

Use the infra role for `sam deploy`. Use the app role for lightweight hotfixes that only need to push new Lambda code.

---

## Security notes

- **Mandatory prefix scoping** — `--stack-prefix` and `--cfn-role-prefix` are required at deploy time. They lock CloudFormation actions, IAM role CRUD, and `iam:PassRole` to named prefixes, preventing privilege escalation to roles outside your application's namespace.
- **`iam:PassRole` scoping** — the infra role can only pass roles whose names start with `CloudFormationExecutionRolePrefix`. This prevents a compromised workflow from passing an admin role to CloudFormation.
- **IAM CRUD scoping** — `SamIamManage` (needed for SAM to create Lambda execution roles) is restricted to `role/${CloudFormationStackNamePrefix}*`. A compromised workflow cannot create or modify roles outside that prefix.
- **GitHub Environments** — for production deployments, enable `UseGitHubEnvironment` and configure required reviewers in GitHub to add a human approval gate before roles can be assumed.
- **Artifact bucket** — set `ArtifactBucketName` to constrain S3 access to a specific bucket.
- **`CAPABILITY_NAMED_IAM`** — required because these templates create named IAM resources. Review the templates before deploying to understand what is being created.
- **Test before prod** — deploy to a sandbox account first and verify GitHub Actions workflows can assume the roles before granting production privileges.
