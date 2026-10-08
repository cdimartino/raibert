# Production deployment

Production is CloudFront in `us-east-1` with a private versioned S3 origin, a private IAM-authenticated Lambda Function URL for `/api/*`, a retained encrypted DynamoDB table, and a CloudFront-scoped WAF. Lambda logs are retained for 30 days and request bodies are not logged.

## Bootstrap

Authenticate to the AWS account containing the `raibert.lol` public hosted zone with a non-root identity. The bootstrap validates the account and DNS before applying infrastructure.

```sh
aws login --profile raibert-admin --remote
AWS_PROFILE=raibert-admin ALERT_EMAIL=you@example.com script/bootstrap_aws
```

Set the resulting deploy-role ARN as the repository variable `AWS_DEPLOY_ROLE_ARN`. Pushes to `main` deploy only after CI succeeds through short-lived GitHub OIDC credentials.

## Safe static publication

`script/deploy_site` validates runtime hashes and the packaged gzip before making AWS calls. It uploads content-hashed runtime files with their final MIME, compression, and immutable-cache headers first. It then uploads assets and JavaScript dependencies, publishes manifests and the app, and publishes `index.html` last. An upload failure stops the release before later publication steps and invalidation.

Deployments intentionally retain previous files. Cached manifests and tabs already open can still request older runtimes and artwork. Do not add `--delete` back to the sync or apply an automatic expiry to current object keys. Retention is separate from S3 noncurrent-version lifecycle rules. A future cleanup needs an explicit client-support horizon and an inventory of retained release manifests.

Rollback uses the previous packaged release with the same deployment script; retained immutable objects remain available. This is dependency-ordered publication, not an atomic transaction across all mutable files. Keep manifest/module contracts backward compatible during rollout. Runtime filenames and headers must stay immutable; upload a new hash for different decoded bytes.

Verify both a fresh session and a tab opened before deployment. Confirm the new runtime and at least one previous runtime return 200 with `Content-Type: application/wasm` and `Content-Encoding: gzip`. Old objects already deleted by earlier releases need separate restoration; removing deletion from future deploys cannot recover them.

## Verification

Verify `GET https://raibert.lol/api/leaderboard`, CloudFront error handling, and Lambda throttle/error alarms after an infrastructure change. Do not insert fake scores in production. The Lambda origin uses AWS IAM authentication and is intentionally unavailable to anonymous direct requests.

## Administration

There is no public administrative API. With an explicitly authenticated administrator profile, use `script/leaderboard_admin list` or `script/leaderboard_admin remove ENTRY_ID`. The tool operates directly on DynamoDB and requires confirmation for removal.

The S3 bucket and DynamoDB table use retained deletion policies. Point-in-time recovery protects the leaderboard table. Review retained resources explicitly before deleting a stack.

## Visitor and gameplay analytics

After deploying the updated stack, open **CloudWatch → Dashboards → raibert-prod-usage** in the hosting AWS account. The `UsageDashboardUrl` stack output provides the direct link. Select a time range to see page views, browser sessions, game starts, game overs, victories, active play seconds, runtime failures, and CDN requests. The bottom table groups page views by referring domain and desktop/mobile input type. CloudWatch can take a few minutes to extract metrics from logs; gameplay reports flush each minute and when leaving or hiding the page.

A session means a browser tab session, surviving reloads; it is not a count of unique people. If session storage is unavailable each load counts as a session. Page views count production page loads with JavaScript enabled. Referrers contain only the hostname (or `direct`); mobile means coarse pointer input. Active play time excludes paused and hidden gameplay; closing a page may lose its final partial minute. Analytics are best effort, client-reported, and can be blocked or spoofed. CDN requests include assets and bots, so they are not visits. There is no historical gameplay backfill.

Tracking runs only on `raibert.lol`, respects Do Not Track and Global Privacy Control, and sends no cookies, visitor identifiers, initials, score submissions, full URLs, or error messages. Validated events are stored in a separate 30-day CloudWatch log group; only seven fixed metrics with a site dimension are extracted. Metrics follow CloudWatch's standard retention. The collector uses a private signed Lambda origin behind the existing API WAF rate limit and has no leaderboard permissions. Dashboard access requires AWS credentials; do not share it publicly.

This change requires an **infrastructure deployment** as well as deploying the static client; use `script/deploy_analytics` below for an existing stack or `script/bootstrap_aws` for initial provisioning. The normal GitHub content deploy does not update Lambda or create the dashboard. AWS Lambda, logs, custom metrics, dashboard, and query charges apply. No external analytics account is needed.

### Activate analytics on the existing stack

With the AWS CLI and Ruby installed, renew the existing administrator login and deploy:

```sh
aws login --profile raibert-admin --remote
AWS_PROFILE=raibert-admin mise exec -- script/deploy_analytics
```

The script discovers the existing artifact bucket from the deployed leaderboard template and uses the AWS CLI directly; SAM is not required. It preserves the deployed leaderboard code package and existing resource metadata. Existing origin hostnames, WAF ARN, and redirect function ARN are retained from CloudFront configuration, so the analytics update does not require additional read access to those unrelated resources. It preserves existing stack parameters, inspects the change set, refuses resource removals or replacements, updates the infrastructure, deploys the static client, and prints the dashboard URL. If the SAM managed bucket is unavailable, set `ARTIFACT_BUCKET` to an existing private deployment bucket in `us-east-1`. Do not use the site content bucket.

### Administrator permissions for analytics deployment

The existing `raibert-admin` user can read the production stack, but the first deployment attempt was denied artifact uploads and access to the SAM transform. An IAM administrator must add the deployment permissions before activation.

1. In the AWS account `129942367502`, open **IAM → Policies → Create policy → JSON**.
2. Paste `infra/analytics-deployer-policy.json` and create a customer managed policy named `RaibertAnalyticsDeployment`.
3. Open **IAM → Users → raibert-admin → Permissions → Add permissions → Attach policies directly**, select `RaibertAnalyticsDeployment`, and attach it.
4. Run the analytics deployment command above. This policy supplements existing site permissions; it is not a replacement for them.

The policy scopes writes to the production stack and its analytics change sets, existing artifact bucket prefix, analytics Lambda and its basic logging role, analytics log group, usage dashboard, and the existing CloudFront distribution. Metric listing and query-result read APIs require wildcard resources. Use a customer managed policy rather than a user inline policy because of [IAM policy size limits](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_iam-quotas.html). The SAM transform permission is required by [CloudFormation access control](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/control-access-with-iam.html).

Deployment was verified on October 6, 2026 using this policy and the existing site permissions. A live browser visit recorded page-view, session-start, and game-start events with HTTP 204 responses; the game loaded and the leaderboard returned HTTP 200. CloudWatch extracted the visitor and gameplay metrics. If AWS reports another denied action during future changes, review the specific action and resource before extending permissions. After initial provisioning, deployment permissions can be removed and a separate dashboard viewing policy retained if desired.

The analytics client changes must be included in `main` before the next GitHub content deployment. A deployment from an older revision will replace the live client and remove its tracking module, even though the dashboard and collector remain provisioned.


## WAF bot safeguards and cost alerts

The firewall keeps the existing blocking rule at 100 API requests per source IP per five minutes. Three new rules begin in Count mode: Amazon IP reputation, 10 leaderboard POSTs per source IP per five minutes, and invalid API routes/methods/body sizes. They record matches but do not yet block. The managed group's individual rules are overridden to Count; a group-level Count override also prevents a newly added managed rule from blocking before review.

Allowed API shapes are GET /api/leaderboard with no body, POST /api/leaderboard up to 1,024 bytes, and POST /api/analytics up to 2,048 bytes. JSON/content validation remains in Lambda. Body inspection overflow fails the allowed-shape check. Rules apply to the raw /api/ path prefix used by the distribution; static game assets are unaffected by these API rules. Existing per-IP API blocking runs first. Sampled requests are disabled on the new rules so score payloads are not newly captured.

Review Count metrics and test multiple players sharing an IP before enabling blocking. Remove both the managed group Count override and its individual Count overrides when intentionally enabling its default actions. Change the two custom Count actions to Block only after checking legitimate traffic. There is no aggregate API cutoff, paid Bot Control, or blanket VPN block.

A traffic alarm detects more than 1,000 CDN requests in five minutes (including assets/bots). This threshold would have flagged the observed 2,188-request spike on October 8; smaller observed spikes stayed below 1,000. A billing alarm detects account-wide estimated month-to-date charges of at least USD 15 using AWS/Billing in us-east-1. Billing is delayed, these are notifications rather than a hard cap, and the alarm resets when monthly estimated charges reset. Both alarms publish through an SNS topic to the AlertEmail stack parameter. The recipient must confirm the SNS subscription email before delivery works.

Existing deployments: apply the reviewed WAF-hardening change set, which preserves deployed application code. The supplemental infra/waf-hardening-policy.json grants the specific WAF, alarm, and SNS permissions needed; it does not grant firewall deletion. The obsolete WAF-removal change set was cancelled. New deployments pass ALERT_EMAIL to script/bootstrap_aws.

Deployed October 8, 2026: stack UPDATE_COMPLETE after the reviewed retry change set. All four rules read back exactly as configured (normalizing AWS base64 match strings). Site and leaderboard returned HTTP 200; analytics rejected a signed invalid payload with HTTP 422; the live browser rendered character selection. The operations dashboard now includes new-rule Count metrics and both alarms, with a matching API readback. SNS email subscription for the configured recipient is PendingConfirmation; delivery is not yet verified. New alarms initially reported INSUFFICIENT_DATA while awaiting evaluation. The first attempt rolled back cleanly because attaching managed rules also requires wafv2:UpdateWebACL on the managedruleset reference; the supplied policy includes this permission. Observation-based promotion from Count to Block remains a separate step.


### Analytics dashboard refresh (October 8, 2026)

The usage dashboard now defaults to the last 24 hours, uses five-minute metric buckets with live partial data enabled, and preserves those periods instead of letting CloudWatch choose hourly aggregation. The former dashboard used 3,600-second buckets without live data; minute-level PageViews were available within four minutes of inspection, confirming the chart display was coarser than the incoming data. A dashboard refresh is still needed to fetch new data; avoid frequent auto-refresh because each refresh reruns the log tables.

The layout includes selected-range totals for all seven analytics metrics, aggregate starts/session and active-minutes/start ratios, visits/gameplay/activity/error charts, referrer and input-device tables, daily UTC activity, last-report freshness, recent anonymous events, and clearly labeled CDN request/download volume. Ratios are not unique-person conversion or completed-session durations. No additional tracking fields or identifiers were introduced. Source log tables cover at most the existing 30-day retention. All five log queries and all three derived metric expressions were checked against AWS data. Live console rendering requires a separately authenticated AWS browser session.


### Bounded runtime-error diagnostics

Client release 2026-10-08.1 reports at most one runtime failure per page load. Error records may include only an allowlisted phase, exception type, browser family, source-file code and numeric line, plus the client release and hashed Ruby runtime filename. Raw messages, full stack traces, full user agents, arbitrary paths/URLs, and identifiers are never sent. Privacy opt-outs still apply. Backend validation rejects unknown fields/values without logging them; diagnostic fields are stored only in the existing 30-day log group, never as new custom-metric dimensions. Historical count-only reports remain accepted and appear as legacy in the dashboard.

The app marks asset loading, runtime downloading, WebAssembly compilation, runtime startup and gameplay separately. This instruments the existing fatal-error path; unrelated console warnings or recoverable audio/network errors do not become fatal-error counts. The source and line are best-effort and may be unknown. Keep the client release allowlist in analytics/handler.rb aligned when changing the release in public/web/analytics.js. Browser-family detection is approximate, not a fingerprint.

Privacy, diagnostic validation, legacy compatibility, deduplication, opt-out, and static packaging checks passed locally. Deploy the backward-compatible collector before the two changed client JavaScript files. No synthetic runtime-error report is inserted into production analytics for testing.

Diagnostics deployment verified on October 8: CloudFormation UPDATE_COMPLETE, collector package hash matched, both live JavaScript files matched the tested source, and CloudFront invalidation completed. The live endpoint rejected an unapproved diagnostic message field with HTTP 422. Browser startup and game start passed with no console errors. Diagnostic dashboard body readback matched. The collector and client diagnostic contract must stay aligned in future releases.
