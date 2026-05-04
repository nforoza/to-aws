# GitHub Actions → AWS OIDC integration (CloudFormation)

Reusable CloudFormation templates that allow GitHub Actions workflows to authenticate with AWS via OIDC — no long-lived credentials stored in GitHub.

Deploy one stack per repository. Each stack creates one scoped IAM policy and one IAM role that only that repository's workflows can assume.

---

## How it works

1. GitHub Actions requests a short-lived OIDC token from GitHub.
2. AWS IAM verifies the token against the account-level OIDC provider.
3. The workflow assumes an IAM role scoped to a specific org/repo/branch — no AWS credentials are stored anywhere.

---

## Repository structure

```
src/
├── github_oidc_provider.yaml    Standalone stack — OIDC provider (once per account)
├── github_aws_integration.yaml  Root stack — wires policies + role for one repository
├── github_sam_policies.yaml     Child stack — SAM deploy policy (Lambda, API GW, EventBridge)
├── github_infra_policies.yaml   Child stack — infra deploy policy (S3 buckets, CloudFormation)
├── github_app_role.yaml         Child stack — IAM role for SAM deployments
├── github_infra_role.yaml       Child stack — IAM role for infrastructure deployments
├── run_deploy.sh                Entry point — choose sam or infra target
├── deploy_oidc.sh               Deploys the OIDC provider standalone stack
├── upload.sh                    Uploads child templates to S3
└── deploy_stack.sh              Deploys one integration stack from env vars
```

---

## Deployment types

Each repository gets exactly one role, determined by its deployment type:

| Type | Policy template | Role template | Role name | Use case |
|---|---|---|---|---|
| `sam` | `github_sam_policies.yaml` | `github_app_role.yaml` | `github-app-<repo>` | Repos that run `sam deploy` |
| `infra` | `github_infra_policies.yaml` | `github_infra_role.yaml` | `github-infra-<repo>` | Repos that manage infrastructure |

**SAM policy** permissions: CloudFormation CRUD, Lambda full lifecycle, IAM role management, API Gateway, EventBridge, S3 artifact access.

**Infra policy** permissions: CloudFormation CRUD, S3 bucket create/configure/delete, `iam:PassRole`.

---

## Quickstart

### 1. Configure `run_deploy.sh`

Edit the shared configuration block at the top of `src/run_deploy.sh`:

```bash
export AWS_REGION=us-east-1
export CF_BUCKET=<s3-bucket-for-cloudformation-templates>
export CF_PREFIX=<s3-key-prefix>
export ARTIFACT_BUCKET=<s3-bucket-for-deployment-artifacts>
export GITHUB_ORG=<your-github-org-or-username>
export GITHUB_BRANCH=main
export CFN_ROLE_PREFIX=github-cfn-execution-
export APPLICATION=<application-name>
export PROJECT=<project-name>
export MANAGED_BY=cloudformation
```

Then add your targets to the `case` block:

```bash
case "${TARGET}" in
  sam)
    export GITHUB_REPO=my-app  STACK_PREFIX=my-app-  POLICY_TYPE=sam
    ;;
  infra)
    export GITHUB_REPO=my-app-infra  STACK_PREFIX=my-app-infra-  POLICY_TYPE=infra
    ;;
esac
```

### 2. Deploy

```bash
./src/run_deploy.sh sam    # deploys the sam target
./src/run_deploy.sh infra  # deploys the infra target
```

`run_deploy.sh` checks whether the OIDC provider already exists (deploys it if not), uploads templates to S3, then deploys the selected integration stack.

---

## Stack architecture

The OIDC provider is a per-account singleton deployed independently. Each repository integration stack is nested:

```
GitHub-Actions-OIDC-Provider          (github_oidc_provider.yaml — shared, once per account)

GitHub-Actions-Integration-<repo>     (github_aws_integration.yaml — root, once per repo)
├── GitHubPoliciesStack               → github_sam_policies.yaml   or github_infra_policies.yaml
└── GitHubRoleStack                   → github_app_role.yaml       or github_infra_role.yaml
```

The OIDC provider ARN is read from the `GitHub-Actions-OIDC-Provider` stack output at deploy time and passed to each integration stack as a parameter.

---

## Stack outputs

### `GitHub-Actions-OIDC-Provider`

| Output | Description |
|---|---|
| `GitHubOidcProviderArn` | ARN of the shared GitHub Actions OIDC provider |

### `GitHub-Actions-Integration-<repo>`

| Output | Description |
|---|---|
| `GitHubRoleArn` | ARN of the deployment role for this repository |
| `ResourceGroupArn` | ARN of the AWS Resource Group for this application |
| `Application` | Application tag applied to all resources |
| `Project` | Project tag applied to all resources |

---

## Parameters reference

### Root stack (`github_aws_integration.yaml`)

| Parameter | Required | Description |
|---|---|---|
| `OidcProviderArn` | Yes | ARN of the OIDC provider (read from `GitHub-Actions-OIDC-Provider` output) |
| `PoliciesTemplateUrl` | Yes | S3 URL of the policies child template |
| `RoleTemplateUrl` | Yes | S3 URL of the role child template |
| `GitHubOrg` | Yes | GitHub organization or username |
| `GitHubRepo` | Yes | Repository that will assume the role |
| `GitHubBranch` | Yes | Branch allowed to assume the role (default: `main`) |
| `RoleName` | Yes | IAM role name — derived from repo name by `deploy_stack.sh` |
| `PolicyName` | Yes | Managed policy name — derived from repo name by `deploy_stack.sh` |
| `ArtifactBucketName` | No | S3 bucket for deployment artifacts. Leave empty to omit S3 access. |
| `CloudFormationStackNamePrefix` | Yes | Scopes CloudFormation actions and IAM role CRUD to stacks with this prefix |
| `CloudFormationExecutionRolePrefix` | Yes | Scopes `iam:PassRole` to roles whose names start with this prefix |
| `Application` | Yes | Application tag (e.g. `trading`) |
| `Project` | No | Project tag (default: `github-actions-oidc`) |
| `DeploymentType` | Yes | `sam` or `infra` — recorded as a tag |
| `ManagedBy` | No | ManagedBy tag (default: `cloudformation`) |

### Role stacks (`github_app_role.yaml`, `github_infra_role.yaml`)

| Parameter | Required | Description |
|---|---|---|
| `GitHubOidcProviderArn` | Yes | Passed automatically by the root stack |
| `GitHubOrg` / `GitHubRepo` / `GitHubBranch` | Yes | OIDC trust condition — only this repo/branch can assume the role |
| `UseGitHubEnvironment` | No | `'true'` to use a GitHub environment subject instead of a branch |
| `GitHubEnvironmentName` | No | GitHub environment name when `UseGitHubEnvironment` is `'true'` |
| `RoleName` | Yes | IAM role name |
| `PolicyArn` | Yes | Passed automatically by the root stack |

---

## Tagging and Resource Groups

All resources are tagged via CloudFormation stack tag propagation:

| Tag | Value | Scope |
|---|---|---|
| `Application` | e.g. `trading` | Integration stacks only |
| `Project` | e.g. `github-actions-oidc` | All stacks |
| `GitHubOrg` | e.g. `nforoza` | Integration stacks only |
| `GitHubRepo` | e.g. `data-collector` | Integration stacks only |
| `DeploymentType` | `sam` or `infra` | Integration stacks only |
| `ManagedBy` | `cloudformation` | All stacks |

Each integration stack creates an `AWS::ResourceGroups::Group` named `github-actions-<repo>` that queries by `Application` + `Project`. Use the **Tag Editor** in the AWS console to find all resources belonging to an application across stacks.

To include your application's own CloudFormation stacks in the same group, tag them with matching `Application` and `Project` values at deploy time:

```bash
aws cloudformation deploy \
  --stack-name my-app-infra-storage \
  --template-file storage.yaml \
  --tags Application=trading Project=data-collector ManagedBy=github-actions
```

---

## Using the role in GitHub Actions

Add `id-token: write` permission and use `aws-actions/configure-aws-credentials@v4`:

**SAM deployment (`sam` type → `github-app-<repo>`):**

```yaml
jobs:
  deploy:
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
          role-to-assume: arn:aws:iam::<account-id>:role/github-app-<repo>
          aws-region: us-east-1

      - run: sam build
      - run: sam deploy --no-confirm-changeset --no-fail-on-empty-changeset
```

**Infrastructure deployment (`infra` type → `github-infra-<repo>`):**

```yaml
jobs:
  deploy:
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
        run: |
          aws cloudformation deploy \
            --template-file storage.yaml \
            --stack-name <stack-prefix>-storage \
            --capabilities CAPABILITY_NAMED_IAM \
            --no-fail-on-empty-changeset \
            --tags Application=trading Project=data-collector ManagedBy=github-actions
```

---

## Security notes

- **Mandatory prefix scoping** — `STACK_PREFIX` and `CFN_ROLE_PREFIX` are required. They lock CloudFormation actions, IAM role CRUD, and `iam:PassRole` to named prefixes, preventing privilege escalation outside your application's namespace.
- **`iam:PassRole` scoping** — the infra role can only pass roles whose names start with `CFN_ROLE_PREFIX`. This prevents a compromised workflow from passing an admin role to CloudFormation.
- **IAM CRUD scoping** — IAM role management is restricted to `role/${STACK_PREFIX}*`. A compromised workflow cannot create or modify roles outside that prefix.
- **`infra` policy S3 scope** — the infra policy grants S3 bucket management on `*`. Once your bucket naming convention is established, scope it by adding a bucket name prefix parameter.
- **GitHub Environments** — for production deployments, enable `UseGitHubEnvironment: 'true'` and configure required reviewers in GitHub to add a human approval gate before the role can be assumed.
- **Artifact bucket** — set `ArtifactBucketName` to constrain S3 artifact access to a specific bucket.
- **`CAPABILITY_NAMED_IAM`** — required because these templates create named IAM resources. Review templates before deploying.
- **Test before prod** — deploy to a sandbox account first and verify GitHub Actions workflows can assume the role before granting production access.
