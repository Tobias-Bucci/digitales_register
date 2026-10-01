# Academic analytics BigQuery examples

## Why event averages are incorrect

`academic_summary_updated` is a **changed snapshot**, not a new participant. A frequent user can contribute many snapshots. GA4 event-level sums/means therefore do not answer “what is the latest overall average among participating users?” Select one latest valid contribution per **pseudonymous `user_id` + academic year + semester**, then average across those users. Use school association from that same snapshot, not the user's current property at report execution time.

Identity method C is used: a cryptographically random installation-local account UUID. **Cross-device user deduplication is not available with this fallback.** The same person can be represented more than once across devices/accounts. Participant counts count pseudonymous IDs, not verified distinct people. Restored local application data may also restore an identity. Do not present these results as a census of students, verified unique individuals, official school performance or competitive school rankings.

The current implementation uses the app's 0–10 numeric representation and equal weighting of non-ignored subject averages; subject averages retain their existing assessment weights. There is no reliable named grading-scale metadata. The query restricts provider category to `digital_register_api`. Do not merge a future different provider/scale into this cohort. Future incompatible scale support needs an explicit reliable scale field and a new schema/report design. Local subject exclusions can affect comparability; describe results as participating installations' app-computed averages.

School IDs are now submitted only under additional academic consent, including on ordinary usage events. See [retention tasks](BIGQUERY_RETENTION.md): GA4 retention does not remove exported raw data.

## Export structure

Daily GA4/Firebase export tables are `events_YYYYMMDD`. `event_name`, `event_timestamp` and `user_id` are top-level fields. `event_params` and `user_properties` are repeated key/value records. This query reads integer metric values from `event_params.value.int_value`, string parameters/properties from `value.string_value`, and school association from `user_properties` on the same event. It uses `ROW_NUMBER`, not `AVG` across all events. No uploaded local fingerprint exists.

Replace the dataset placeholder below with the developer's existing export dataset. The document contains no real Firebase project ID. Use a real **single** academic year and semester; the example targets 2026_2027 and semester 1. Adjust the date range to the full school year and any relevant export-delivery window. The current domain's school-year boundary is July. Do not limit to recently active users unless that is explicitly the reporting population.

Use daily tables only. The `_TABLE_SUFFIX` condition excludes `events_intraday_*` to avoid counting daily and intraday copies. Re-run after late data has reached daily tables. Enabling export is not guaranteed to populate a historical period that predates export. BigQuery access, costs, retention, region and scheduling must be configured manually. This example has not been run against a live dataset.

## Latest participant snapshots and overall aggregate

```sql
DECLARE target_year STRING DEFAULT '2026_2027';
DECLARE target_semester STRING DEFAULT '1';

CREATE TEMP TABLE latest_snapshots AS
WITH extracted AS (
  SELECT
    user_id,
    event_timestamp,
    event_bundle_sequence_id,
    batch_event_index,
    (SELECT value.string_value FROM UNNEST(event_params)
      WHERE key = 'academic_year') AS academic_year,
    (SELECT value.string_value FROM UNNEST(event_params)
      WHERE key = 'semester') AS semester,
    (SELECT value.int_value FROM UNNEST(event_params)
      WHERE key = 'grade_average_tenths') AS average_tenths,
    (SELECT value.int_value FROM UNNEST(event_params)
      WHERE key = 'snapshot_schema_version') AS schema_version,
    (SELECT value.string_value FROM UNNEST(event_params)
      WHERE key = 'grade_count_bucket') AS grade_bucket,
    (SELECT value.string_value FROM UNNEST(event_params)
      WHERE key = 'subject_count_bucket') AS subject_bucket,
    (SELECT value.string_value FROM UNNEST(user_properties)
      WHERE key = 'school_id') AS school_id,
    (SELECT value.string_value FROM UNNEST(user_properties)
      WHERE key = 'demo_mode') AS demo_mode,
    (SELECT value.string_value FROM UNNEST(user_properties)
      WHERE key = 'school_api_type') AS provider
  FROM `<PROJECT>.<DATASET>.events_*`
  WHERE REGEXP_CONTAINS(_TABLE_SUFFIX, r'^[0-9]{8}$')
    AND _TABLE_SUFFIX BETWEEN '20260701' AND '20270731'
    AND event_name = 'academic_summary_updated'
), valid AS (
  SELECT * FROM extracted
  WHERE user_id IS NOT NULL AND user_id != ''
    AND REGEXP_CONTAINS(user_id,
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
    AND academic_year = target_year
    AND academic_year != '2099_2100' -- Synthetic debug year.
    AND semester = target_semester
    AND semester IN ('1', '2', 'year')
    AND schema_version = 1
    AND average_tenths BETWEEN 0 AND 100
    AND grade_bucket IN ('1_5', '6_10', '11_20', '21_40', '41_plus')
    AND subject_bucket IN ('1_5', '6_10', '11_plus')
    AND REGEXP_CONTAINS(school_id, r'^school_[0-9]{4}$')
    AND demo_mode = 'false'
    AND provider = 'digital_register_api'
)
SELECT * EXCEPT(snapshot_rank)
FROM (
  SELECT *, ROW_NUMBER() OVER (
    PARTITION BY user_id, academic_year, semester
    ORDER BY event_timestamp DESC,
      event_bundle_sequence_id DESC, batch_event_index DESC
  ) AS snapshot_rank
  FROM valid
)
WHERE snapshot_rank = 1;

-- Each row is now one participant's latest valid snapshot for this period.
SELECT academic_year, semester,
  COUNT(DISTINCT user_id) AS contributing_pseudonymous_users,
  AVG(average_tenths / 10.0) AS average_of_latest_app_averages
FROM latest_snapshots
GROUP BY academic_year, semester
HAVING COUNT(DISTINCT user_id) >= 30;

-- School-level suppression is mandatory for any displayed school result.
SELECT school_id, academic_year, semester,
  COUNT(DISTINCT user_id) AS contributing_pseudonymous_users,
  AVG(average_tenths / 10.0) AS average_of_latest_app_averages
FROM latest_snapshots
GROUP BY school_id, academic_year, semester
HAVING COUNT(DISTINCT user_id) >= 30;
```

`batch_event_index` is part of the current GA4 export schema. Verify its availability in the developer's exported tables, especially older export periods, before running; omit that secondary tie-breaker if absent. Timestamps are assigned by Firebase; the app does not add grade dates or precise application timestamps. If two conflicting events have identical ordering fields, investigate before treating one as a definitive newest value. For recurring production reporting, materialize controlled aggregates after daily-table updates and account for late arrivals.

A “latest valid” snapshot may outlive a user's local consent revocation: revocation stops future device submissions, but no event is emitted under denied consent and no backend deletion/tombstone workflow exists. Consequently an export query cannot infer current consent eligibility or erase historical rows from local revocation. Do not invent such a guarantee. If an operational deletion workflow is later added, incorporate its verified deletion/tombstone records into aggregate derivation and retention procedures.

## Cohort rules and reporting limits

- Suppress every displayed group, including an overall cohort, below 30 **distinct pseudonymous IDs**. This is a project engineering rule, not a claim of legal anonymity or a universal legal threshold.
- Show participant count with an overall platform statistic. Suppressed groups must not be exposed by an alternative drill-down or download.
- No “best schools”, “worst schools” or student rankings. No subject/class/teacher/age/gender/attendance dimensions.
- Demo is excluded at the app gate and again in this query. Synthetic debug data use 2099_2100 and must be excluded from production reporting even if DebugView/export settings change.
- Unknown/custom register URLs and ambiguous catalog aliases have no school association and no academic submission. This intentionally limits coverage rather than guessing a school.
- Restrict raw pseudonymous data access; only appropriately suppressed aggregates belong in any future public UI.
- Averages are over current app-computed averages, rounded to tenths before upload. They are not weighted by number of grades or events. Per-user rounding and missing nonparticipants affect estimates.
- Do not combine `semester='year'` with semesters 1/2 in one mean; one installation can have multiple distinct period snapshots. Use a specified period and compatible provider/scale.

Authoritative references: [GA4 export schema](https://support.google.com/analytics/answer/7029846?hl=en-EN), [Firebase export configuration](https://firebase.google.com/docs/projects/bigquery-export). Dataset-specific schema, permissions, costs and query behavior remain developer verification steps.
