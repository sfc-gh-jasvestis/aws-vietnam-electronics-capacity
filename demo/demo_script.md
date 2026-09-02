# Production Capacity Planning

**Vietnam - Electronics Manufacturing**
Use case: Capacity Planning

> Production Capacity Planning for Vietnam - ML.FORECAST and Dynamic Tables power real-time capacity planning intelligence for electronics manufacturing in Thai Nguyen & Hai Phong.

## Why Snowflake

Snowflake delivers capacity planning intelligence for Vietnamese electronics manufacturing - Dynamic Tables maintain real-time dashboards, ML.FORECAST projects key metrics, and Cortex AI generates recommendations

- **ML.FORECAST for capacity planning** - Only demo for Vietnamese electronics manufacturing
- **ML.ANOMALY_DETECTION early warning** - Detects deviations before impact
- **AI recommendations** - Cortex AI actionable guidance
- **Vietnamese context** - Local names, VND economics

## What is deployed

| | |
|---|---|
| Database | `VIETNAM_ELECTRONICS_CAPACITY` |
| Service | `VIETNAM_ELECTRONICS_CAPACITY_APP` |
| Compute pool | `SEA_DEMOS_VIETNAM_POOL` |
| Dimension table | `RAW.DOCUMENTS` (20 rows) |
| Fact table | `RAW.METRICS` (250,000 rows, 90 days) |
| Curated layer | `CURATED.PERFORMANCE_SUMMARY`, `CURATED.TREND_ANALYSIS`, `CURATED.KPI_SUMMARY` |
| Currency | VND (₫) |

Regions in play: Ho Chi Minh City, Hanoi, Binh Duong, Dong Nai, Can Tho
Segments: SMT Line, Assembly Line, Test Line, Packaging

Dynamic tables are created suspended and refreshed on demand:

```bash
./refresh_demo_data.sh VIETNAM_ELECTRONICS_CAPACITY
```

## KPI cards

Every card below is served live from `CURATED.KPI_SUMMARY`. The app keeps the
original literal as a fallback, so it still renders if Snowflake is unreachable.

| Card | Value | Backed by |
|---|---|---|
| Factory Utilization | `89%` | average per event |
| Output (MTD) | `4.2M units` | total across Documents |
| Yield Rate | `97.8%` | average per event |
| Lines Active | `24` | total across Documents |
| Cycle Time | `12.4s` | average per event |
| OEE | `84%` | average per event |
| Bottleneck Tool | `SMT-3` | fixed label (not numeric) |

## Demo flow

1. Overview
2. Analytics
3. AI Intelligence
4. Ask AI
5. Architecture

## Talking points

- **100K operations** - tracked in Thai Nguyen & Hai Phong
- **500K metrics** - time-series data points
- **5K assets** - monitored
- **100 docs** - searchable

## Business impact

- Vietnam electronics manufacturing sector growing rapidly (GSO Vietnam)
- AI improves outcomes 15-30% (McKinsey)
- Vietnam FDI strong in this sector (MPI)
- Real-time analytics reduces response 60-80% (Gartner)

---
Generated from `generator/demo_specs/aws-vietnam-electronics-capacity.json`. Do not hand-edit: run
`python3 generator/gen_repo_docs.py aws-vietnam-electronics-capacity` instead.
