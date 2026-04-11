aws cloudformation deploy \
  --template-file github_aws_integration.yaml \
  --parameter-overrides file:///github_aws_integration_params.json \
  --stack-name github-aws-integration-repo-to-aws \
  --region us-east-1 \
  --capabilities CAPABILITY_NAMED_IAM
