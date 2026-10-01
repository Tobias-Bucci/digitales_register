# BigQuery retention — external administrator task

As reported in the task specification (not independently verified in Console): project `digitales-register-ca085`, GA4 property `538053533`, BigQuery region **EU**, daily export on; streaming, advertising-ID export and separate user-data export off. GA4 uses 14 months with reset on new activity. Google Signals, Ads linking, advertising personalization and user-provided data remain off.

**GA4 retention does not delete exported BigQuery raw data.** Recommended project target: at most approximately 14 months of raw records, unless an independently reviewed factual/legal reason justifies another duration. The repository/app does not configure cloud retention, credentials or administrative access.

Administrator checklist:

1. Confirm dataset location and actual export settings; record the check date.
2. Inspect dataset default table expiration, individual table expiration and any partition expiration. Daily `events_YYYYMMDD` shards usually require table TTL; do not assume partitioned storage.
3. Configure default expiration for future tables; inspect/adjust **existing tables separately**. A changed dataset default does not retroactively alter their expiry.
4. Verify actual exporter-created tables honor expiration; explicitly review jobs, copied tables, materialized views, scheduled outputs and backups/time-travel recovery behavior. A default is not proof of a complete data-age policy.
5. Align expiration with event dates and late exports. Record the selected duration and operational deletion process; monitor tables lacking TTL. Verify actual deletion behavior and authorized access.
6. Update all four user-facing `privacyDetails.retention.body` values to the **verified actual** retention. Until verified, the app describes the 14-month BigQuery duration as a target requiring review.
7. Use latest snapshot per `user_id + academic_year + semester` in [query examples](ANALYTICS_BIGQUERY_EXAMPLES.md). Suppress published groups below 30 pseudonymous IDs; apply the same policy to exports/downloads.

Local `resetAnalyticsData()` does not delete GA4 or BigQuery history. Local consent withdrawal cannot tell SQL queries which historic user has withdrawn; no deletion/tombstone backend exists. A manual privacy request needs an operational process and legal review, not a fictitious automatic deletion guarantee.

References checked 2026-10-01: [dataset expiration](https://docs.cloud.google.com/bigquery/docs/updating-datasets), [table expiration](https://docs.cloud.google.com/bigquery/docs/managing-tables), [Firebase BigQuery export](https://firebase.google.com/docs/projects/bigquery-export).
