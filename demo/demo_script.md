# Vietnam Electronics Line Capacity

**Vietnam - Electronics Assembly Lines (SMT, through-hole and wave, final assembly, functional test, box build and packing)**
Use case: Committed build-plan attainment and capacity-constraint risk

> Capacity planning for a synthetic network of 28 assembly lines across 5 Vietnamese cities: dynamic tables, a holdout-evaluated constraint-risk classifier, a plan-attainment forecast and grounded AI answers.

## Why Snowflake

- **Dynamic tables** reconcile plan attainment, queue hours per unit and line availability from RAW line data, with checks in `run_core.py`
- **Constraint-risk classification** gives a holdout-evaluated next-7-day capacity-constraint probability per line
- **Plan-attainment forecast** projects 14 days of network-wide attainment with prediction intervals
- **Grounded AI**: the Cortex Agent (Analyst over a semantic view, plus Search over SOPs) shows its SQL and SOP citations
- **Live telemetry**: a native simulator (Snowflake only) or IoT Core, S3 and Snowpipe (AWS build), then an alert and email

## What is built

| | |
|---|---|
| Dimension table | `RAW.PRODUCTION_LINES` (28 rows) |
| Fact table | `RAW.LINE_DAILY` (2,520 line-days, 90 days) |
| Curated layer | `CURATED.KPI_SUMMARY`, `PERFORMANCE_SUMMARY`, `CONSTRAINT_CAUSES`, `TREND_ANALYSIS` |
| ML | `ML.CONSTRAINT_RISK_SCORES`, `ML.CONSTRAINT_RISK_HOLDOUT_METRICS`, `ML.ATTAINMENT_FORECAST`, `ML.THROUGHPUT_GAP_ANOMALIES` |

Cities: Bac Ninh, Bac Giang, Hai Phong, Thai Nguyen, Bien Hoa (Vietnamese cities used as regions; plants, lines, customers and planners are fictional).
Line types: SMT, Through-Hole and Wave, Final Assembly, Functional Test, Box Build and Packing.

## KPI cards (live from `CURATED.KPI_SUMMARY`; no fallback values)

| Card | Value from the seeded data |
|---|---|
| Plan Attainment | 98.4% |
| Capacity Constraints | 161 |
| Queue Hours per Unit | 0.89 h |
| WIP Arrivals (units) | 6,530,474 |
| Line Availability | 99.1% |
| Lines Monitored | 28 |
| Backup Station Coverage | 56.8% |

Values are synthetic. A rebuild reproduces them because the data is HASH-seeded; dates are relative to the build day.

## Demo flow

1. Executive Cockpit: KPIs, daily plan attainment, unit shortfall by root cause, assembly line table
2. Predictive: holdout metrics, risk bands, 14-day plan-attainment forecast, throughput gap anomalies
3. Capacity Health: line availability, backup station coverage, PM compliance against plan attainment, then generate the action memo
4. Live IoT: run `CALL APP.SIMULATE_TELEMETRY(20)` (Snowflake only) or `python aws/publish_telemetry.py --count 20` (AWS build). Then run `EXECUTE ALERT APP.LIVE_ALARM_ALERT` and show the alert log and email.
5. Ask AI: the Cortex Agent answers metric questions through the semantic view and cites SOPs from Cortex Search. The SQL is shown.
6. QuickSight (AWS build): the same Snowflake tables through DIRECT_QUERY
7. Architecture: both builds side by side

## Talking points

- The committed build plan tightens over the 90 days, so attainment drifts down late in the window. Per-line attainment ranges from 97.1% to 99.7%; Box Build and Packing is the lowest line type and Hai Phong the lowest city.
- Packaging material shortages cost the most units of the 14 constraint causes, ahead of label printer downs and component shortages; operator shortages occur more often than component shortages but cost fewer units.
- 15 of 28 lines have fewer qualified backup stations than their critical product family needs.
- The risk model is evaluated on a time-based holdout: precision 0.42 and recall 0.25 at 0.5, against a 0.32 base rate. Present it as triage for the weekly capacity review, not a guarantee; it misses most constraints at this threshold.
- Site-wide grid power dips are excluded from constraint labels, because the line does not cause them.

## Business impact

Use only the sourced references in `README.md` (Business Impact).
