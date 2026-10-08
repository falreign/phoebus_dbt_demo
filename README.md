# Phoebus Loyalty Recognition – dbt project

Turns the Phoebus operational data (casino management, loyalty, POS, hotel), landed by **Fivetran**, into a
**prescriptive daily worklist for hosts and floor staff**: *which guest, why they deserve recognition right now,
what to do, who should do it, what it may cost, and what to say.*

```
SQL Server (phoebus_gaming, Change Tracking)
        │  Fivetran SQL Server connector
        ▼
BigQuery  phoebus_gaming_cms | _loy | _pos | _hotel | _ref        ← raw, snake_case, _fivetran_deleted
        │  dbt (Fivetran Transformations for dbt Core, runs after each sync)
        ▼
staging (views) → intermediate (guest-day facts, metric events) → recognition marts
                                                        └─ rpt_daily_recognition_worklist  ← hosts / BI / Slack
```

## How the logic is built (DRY)

| Layer | Models | Idea |
|---|---|---|
| staging | `stg_*` | Rename/clean only. **Sensitive fields (SSN, ID numbers, address, email, phone) are not carried forward.** |
| intermediate | `int_guest_activity_daily` | One row per guest per gaming day. Gaming / dining / hotel / jackpots are unioned onto **one** column list; the `measure_cols` macro zero-fills what a source lacks. |
| | `int_guest_cumulative_daily` | Lifetime running totals, generated from `var('cumulative_metrics')`. |
| | `int_guest_metric_events` | Everything becomes the same shape: `(player_id, event_date, metric_name, metric_value, prior_value)` – cumulative totals, visit streaks, comebacks, big wins, tier upgrades, birthdays, anniversaries. |
| | `int_guest_rg_signals`, `int_guest_comp_budget` | Responsible-gaming signals; recent comps and 30-day recognition spend. |
| marts | `dim_guest_360` | One row per guest: tier, lifetime value, preferences, presence (on property / in house), **eligibility**. |
| | `fct_guest_milestones` | Joins events to the rules seed: a rule fires when `metric_value >= threshold AND prior_value < threshold`. No milestone-specific SQL. |
| | `fct_recognition_recommendations` | Today's actionable milestones, scored and given a **status** (below). |
| | `rpt_daily_recognition_worklist` | One row per guest, ranked per property. This is what hosts read. |

### Add a new milestone = add one CSV row
`seeds/loyalty_milestone_rules.csv` (42 rules shipped): family, metric, threshold, lead/window days, reward type and budget,
owner, priority, the **recommended action** and the **talking point** (`{first_name}`, `{value}` placeholders).
A brand-new *cumulative* metric additionally needs one line in `dbt_project.yml → vars.cumulative_metrics`.

### Recommendation statuses
| Status | Meaning |
|---|---|
| `RECOMMEND` | Go ahead. Action, owner, approved reward and talking point are ready. |
| `RG_CHECK_IN` | Responsible-gaming signals (extended play, or losses far above the guest's own norm). **No gaming incentives**; the host gets a quiet check-in script instead. Sorted to the top of the worklist. |
| `SUPPRESSED_COOLDOWN` | Recently comped (`recognition_cooldown_days`, `recognition_cooldown_min_usd`) – unless priority ≥ `cooldown_override_priority`. |
| `SUPPRESSED_BUDGET` | The tier's rolling 30-day budget (`seeds/recognition_budget_guardrails.csv`) is used up. |
| `INELIGIBLE` | Not a loyalty member, inactive, **self-excluded, banned**, deceased, or under `min_gaming_age`. Never reaches a worklist. |

Approved reward = `min(rule budget, remaining tier budget)`. All thresholds are variables in `dbt_project.yml`.

## Setup

1. **Fivetran** – SQL Server connector on `phoebus_gaming` in *Change Tracking* mode (the generator's
   `phoebus_change_tracking.sql` grants `VIEW CHANGE TRACKING`), destination BigQuery. Fivetran creates one destination
   schema per source schema. **Check the names it created** and set `fivetran_schema_prefix` accordingly
   (default expects `phoebus_gaming_cms`, `phoebus_gaming_loy`, `phoebus_gaming_pos`, `phoebus_gaming_hotel`, `phoebus_gaming_ref`).
   Fivetran lowercases SQL Server names and drops the separators (`PlayerID` -> `playerid`, table `PlayerSession` -> `playersession`).
   The staging models match columns with the `fv_cols` macro, which ignores case and underscores, so either style works. Multi-word **table**
   names need an `identifier:` in `models/staging/phoebus/_phoebus__sources.yml` (already set for `playersession` and `tierhistory`);
   change those two lines if your tables are named differently.
2. **Run locally**
   ```bash
   cp profiles.example.yml ~/.dbt/profiles.yml     # edit project / dataset
   dbt deps
   dbt seed
   dbt build                                         # models + all tests
   dbt source freshness                              # Fivetran lag check
   ```
   Back-test any day: `dbt build --vars '{as_of_date: "2026-10-07"}'`.
3. **(Alternative to dbt Cloud) Fivetran Transformations for dbt Core** – add this repo as a transformation project, pick the BigQuery destination,
   and trigger it after the SQL Server connector syncs (integrated scheduling). Job steps: `dbt deps`, `dbt seed`, `dbt run`, `dbt test`.
   With the trickle generator feeding SQL Server every 10–15 minutes, the worklist stays "live".
4. **Consume** `rpt_daily_recognition_worklist` from Looker / Looker Studio / Sigma, a Slack alert, or a host tablet.
   Example: `analyses/host_worklist_for_property.sql`.

## Deploying on dbt Cloud (BigQuery)

1. **Git** – push this folder to its own repo (or keep it in a repo subfolder and set *Project subdirectory* in dbt Cloud).
   ```bash
   cd phoebus_dbt && git init && git add . && git commit -m "Phoebus loyalty recognition"
   git remote add origin <your-repo-url> && git push -u origin main
   ```
2. **BigQuery service account** – roles: *BigQuery Job User* (project), *BigQuery Data Editor* (the project dbt writes to),
   *BigQuery Data Viewer* on the Fivetran datasets (`phoebus_gaming_*`). Create a JSON key for it.
3. **dbt Cloud project** – New project → BigQuery → upload the JSON key → pick the repo.
   Location must match the Fivetran datasets (e.g. `US`). Development credentials: a personal dataset such as `dbt_<you>`.
4. **Production environment** – Deploy → Environments → *Deployment* (type Production), dbt version *Latest*, BigQuery credentials with
   dataset `phoebus_dbt`. dbt writes `phoebus_dbt_staging`, `phoebus_dbt_intermediate`, `phoebus_dbt_recognition`, `phoebus_dbt_reference`
   (the worklist is `phoebus_dbt_recognition.rpt_daily_recognition_worklist`).
5. **Deploy job** `phoebus-recognition-refresh` – command `dbt build` (seeds + models + tests in dependency order; dbt Cloud runs `dbt deps`
   automatically), tick *Run source freshness*, schedule by cron, e.g. `7,22,37,52 * * * *` (UTC) to run a few minutes after a 15-minute Fivetran sync.
6. **If Fivetran lands data in a different GCP project** than dbt writes to, add `--vars '{fivetran_database: "<raw-project>"}'`
   to the job command (and `fivetran_schema_prefix` if the dataset names differ).
7. **Trigger on demand** (optional, e.g. from Cloud Scheduler or a Fivetran webhook handler):
   ```bash
   curl -X POST "https://<your-access-url>/api/v2/accounts/<ACCOUNT_ID>/jobs/<JOB_ID>/run/" \
        -H "Authorization: Token <DBT_CLOUD_API_TOKEN>" -H "Content-Type: application/json" \
        -d '{"cause": "after Fivetran sync"}'
   ```

**First-run checklist:** run the job once manually. Failures are almost always (a) a dataset/column name that differs from what Fivetran
created – fix `fivetran_schema_prefix` or the `stg_*` model, (b) dataset location mismatch, or (c) missing BigQuery permissions.

## Tests shipped
Uniqueness / not-null / relationships / accepted values, plus **business-rule tests** that fail the build if:
an ineligible (self-excluded, banned, under-age…) guest reaches a worklist; a flagged guest is offered a gaming incentive or any reward value;
a flagged guest receives a celebratory script; a reward exceeds the remaining tier budget; or a guest appears twice in one property's worklist.

## Verification status
Developed and tested end-to-end on **DuckDB** against data produced by the Phoebus generator (8,000 players, 365 days, Fivetran-style
schema/column naming): 22 models, 2 seeds, 40+ tests all pass. SQL uses dbt cross-database macros (`dateadd`, `datediff`, `listagg`, type macros)
so it is expected to run on BigQuery unchanged, but it was first run against BigQuery in dbt Cloud, which surfaced three environment issues now handled/documented: dataset **location** must match Fivetran's, stale datasets created in the wrong location must be deleted, and Fivetran's column naming (above).

## Notes & simplifications
* Lifetime metrics count from the data present (a guest's history before the generator's window is not known).
* "Theoretical win" is used as the casino's value measure; it is only ever used to rank/qualify, never shown to guests.
* Calendar milestones (birthday, membership anniversary) are generated for a window around today (`calendar_window_days`), not back-filled.
* "Live presence" is gaming-day based (activity today / hotel stay tonight), not real-time floor location.
* Tables are rebuilt each run (a few seconds at this scale). If volumes grow, make `int_guest_activity_daily` incremental.
* Rule thresholds, budgets and wording are illustrative defaults – have Marketing / Compliance / Responsible Gaming review them before production use.
