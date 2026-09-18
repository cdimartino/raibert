# Production deployment

Production is CloudFront in `us-east-1` with a private versioned S3 origin, a private IAM-authenticated Lambda Function URL for `/api/*`, a retained encrypted DynamoDB table, and a CloudFront-scoped WAF. Lambda logs are retained for 30 days and request bodies are not logged.

## Bootstrap

Authenticate to the AWS account containing the `raibert.lol` public hosted zone with a non-root identity. The bootstrap validates the account and DNS before applying infrastructure.

```sh
aws login --profile raibert-admin --remote
AWS_PROFILE=raibert-admin script/bootstrap_aws
```

Set the resulting deploy-role ARN as the repository variable `AWS_DEPLOY_ROLE_ARN`. Pushes to `main` deploy only after CI succeeds through short-lived GitHub OIDC credentials.

## Verification

Verify `GET https://raibert.lol/api/leaderboard`, CloudFront error handling, and Lambda throttle/error alarms after an infrastructure change. Do not insert fake scores in production. The Lambda origin uses AWS IAM authentication and is intentionally unavailable to anonymous direct requests.

## Administration

There is no public administrative API. With an explicitly authenticated administrator profile, use `script/leaderboard_admin list` or `script/leaderboard_admin remove ENTRY_ID`. The tool operates directly on DynamoDB and requires confirmation for removal.

The S3 bucket and DynamoDB table use retained deletion policies. Point-in-time recovery protects the leaderboard table. Review retained resources explicitly before deleting a stack.
