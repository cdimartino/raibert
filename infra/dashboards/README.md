# RaiBert cost and operations dashboards

The usage dashboard is also maintained in infra/site.yml and managed by the production CloudFormation stack; the cost and operations dashboards are standalone.

These definitions target the production resources discovered in account 129942367502 on October 8, 2026. They are standalone CloudWatch dashboards, separate from the existing CloudFormation-managed usage dashboard. Update physical resource IDs if resources are replaced.

## Data freshness

The cost dashboard defaults to the last 24 hours. Traffic, transfer, Lambda, logs, and database charts use five-minute buckets with live partial data enabled, as do operations charts. Billing widgets retain a 14-day window and storage a seven-day window because their source metrics arrive less often.

Collection and screen refresh are separate. Analytics events are sent immediately and active play time is flushed every 60 seconds. AWS service metrics can take a few minutes to arrive; charts do not need a new collector or higher-resolution custom metrics. Billing estimates are published several times daily and S3 storage once daily, with possible delivery delay. Sparse event metrics (such as runtime failures and victories) only report when an event occurs. Gaps must not be filled with invented zeroes or stale values.

In the CloudWatch console, choose **Refresh options → 5 Minutes** for regular updates. Auto-refresh is a console control, not a supported DashboardBody property. On analytics, each refresh also reruns the Logs Insights tables and incurs query charges. Keep a relative time range ending now; an absolute historical range will not advance with refresh.

References: [AWS live data](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/cloudwatch-live-data.html), [refresh controls](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/change_dashboard_refresh_interval.html), [daily S3 metrics](https://docs.aws.amazon.com/AmazonS3/latest/userguide/cloudwatch-monitoring.html).

## Previous publication status

October 9, 2026: published the five-minute cost usage charts and live-data settings for cost and operations using the `raibert-admin` IAM user. Both dashboard writes returned empty validation messages.

Published on October 8, 2026 as raibert-prod-operations and raibert-prod-cost. Both PutDashboard calls returned empty DashboardValidationMessages; GetDashboard readbacks exactly matched these files. Billing total and service search queries returned data (latest account-wide estimate: USD 2.01). Cost Explorer access works. Both named leaderboard alarms returned OK. DescribeAlarms must specify the two alarm names; listing by prefix requires broader access than this policy grants.

All 23 operations metric queries completed successfully over a seven-day window: 22 returned samples and WAF BlockedRequests returned none. Missing samples are not proof of zero activity or healthy service. Layout bounds and non-overlap were checked locally. AWS dashboard validation passed. Browser rendering remains unverified because the in-app browser requires a separate AWS console sign-in.

## Required administrator setup

Attach dashboard-access-policy.json as a supplemental policy to raibert-admin. It grants writes only to the two new dashboards, reads of production alarms, and account cost queries. Existing metric-read permissions remain necessary. This file does not grant permission to modify IAM or billing preferences.

In AWS Billing preferences, enable Receive CloudWatch billing alerts. AWS/Billing metrics are now publishing after this setup. Billing charts use account-wide estimated month-to-date charges; they are not project-specific costs, daily spend, final invoices, or forecasts. The service breakdown populates from published billing metrics. A blank chart must not be read as $0.

AWS documentation: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/gs_monitor_estimated_charges_with_cloudwatch.html

## Publish and verify

From the repository root, verify the caller is arn:aws:iam::129942367502:user/raibert-admin:

```sh
aws sts get-caller-identity --profile raibert-admin
aws cloudwatch put-dashboard --dashboard-name raibert-prod-operations --dashboard-body file://infra/dashboards/raibert-prod-operations.json --profile raibert-admin --region us-east-1
aws cloudwatch put-dashboard --dashboard-name raibert-prod-cost --dashboard-body file://infra/dashboards/raibert-prod-cost.json --profile raibert-admin --region us-east-1
aws cloudwatch get-dashboard --dashboard-name raibert-prod-operations --profile raibert-admin --region us-east-1
aws cloudwatch get-dashboard --dashboard-name raibert-prod-cost --profile raibert-admin --region us-east-1
```

Inspect DashboardValidationMessages from each write, compare retrieved bodies with the local files, then open both dashboards and verify rendering, alarm access, and metric data. Billing metrics may take time to appear. The temporary billing and alarm-permission notices have been removed after verification.

The dashboards use existing service metrics. No additional telemetry, log queries, scheduled collector, or paid CloudFront additional metrics are enabled. Normal CloudWatch dashboard pricing applies. Cost attribution specifically to RaiBert requires separate billing verification; account data also contains unrelated services.
