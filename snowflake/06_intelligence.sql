-- ============================================================================
-- 06_INTELLIGENCE.SQL - search, anomaly detection, semantic view, agent,
-- live-telemetry alert and on-demand refresh DAG.
-- Run with snowflake/run_intelligence.py (substitutes checked __DEMO_DB__ /
-- __DEMO_WH__ / __ALERT_EMAIL__). Requires 00-05, plus 08 (Snowflake only) or
-- aws/setup_aws.py (AWS build) for RAW.LIVE_TELEMETRY.
-- Alerts and tasks are created SUSPENDED; run them with EXECUTE ALERT / EXECUTE TASK.
-- ============================================================================
USE DATABASE __DEMO_DB__;
CREATE SCHEMA IF NOT EXISTS SEARCH;
CREATE SCHEMA IF NOT EXISTS APP;

-- ---------- Synthetic capacity-constraint SOP corpus (clearly synthetic SOPs) ----------
CREATE OR REPLACE TABLE SEARCH.CAPACITY_DOCS AS
WITH causes AS (
  SELECT DISTINCT r.ROOT_CAUSE, g.CATEGORY
  FROM RAW.LINE_DAILY r JOIN RAW.PRODUCTION_LINES g ON g.ID = r.ENTITY_ID
  WHERE r.ROOT_CAUSE IS NOT NULL AND r.CONSTRAINT_COUNT > 0
)
SELECT
  'SOP-' || LPAD(ROW_NUMBER() OVER (ORDER BY CATEGORY, ROOT_CAUSE)::VARCHAR, 3, '0') AS DOC_ID,
  'SOP' AS DOC_TYPE,
  CATEGORY,
  ROOT_CAUSE,
  CATEGORY || ' - ' || ROOT_CAUSE || ' capacity response' AS TITLE,
  'Synthetic demo SOP. Line type: ' || CATEGORY || '. Constraint cause: ' || ROOT_CAUSE || '. '
  || 'Step 1: log the constraint in the MES, re-sequence work orders by committed ship date and notify the line capacity planner. '
  || 'Step 2: ' || CASE
       WHEN ROOT_CAUSE ILIKE '%feeder%' OR ROOT_CAUSE ILIKE '%changeover%' THEN 'compare the setup time with the planned changeover window, pre-kit feeders or fixtures for the next two work orders offline, and group work orders that share a setup.'
       WHEN ROOT_CAUSE ILIKE '%shortage%' AND ROOT_CAUSE NOT ILIKE '%operator%' THEN 'confirm stock and inbound delivery time with the materials team, pull forward work orders whose materials are already kitted, and switch to the approved alternate part or material if one exists.'
       WHEN ROOT_CAUSE ILIKE '%operator%' THEN 'move cross-trained operators from lines that are ahead of plan and confirm the overtime plan with the shift lead.'
       WHEN ROOT_CAUSE ILIKE '%down%' OR ROOT_CAUSE ILIKE '%failure%' THEN 'move work orders to a backup station or line qualified for the product family and request an equipment engineer estimate for return to production.'
       WHEN ROOT_CAUSE ILIKE '%hot-order%' THEN 'limit hot orders to the agreed share of line capacity and confirm priority changes with the planning lead.'
       WHEN ROOT_CAUSE ILIKE '%retest%' THEN 'add a retest slot on a qualified tester, and send repeat failures to failure analysis instead of the retest queue.'
       WHEN ROOT_CAUSE ILIKE '%requalification%' THEN 'run the golden-unit check on the new test program, release the tester for products that passed and hold the rest until results pass.'
       WHEN ROOT_CAUSE ILIKE '%power%' THEN 'confirm facility power status, follow the restart sequence and run first-article checks before the line resumes.'
       ELSE 'inspect the affected station, record the lost hours and escalate to the area manager if recovery exceeds one shift.'
     END
  || ' Step 3: if the throughput gap stays above 5% or the queue exceeds 300 units after recovery, raise the line to the daily capacity review. '
  || 'Step 4: record the root cause, lost line hours and the unit shortfall in the capacity log.' AS CONTENT
FROM causes;

CREATE OR REPLACE CORTEX SEARCH SERVICE SEARCH.CAPACITY_SOP_SEARCH
  ON CONTENT
  ATTRIBUTES CATEGORY, ROOT_CAUSE
  WAREHOUSE = __DEMO_WH__
  TARGET_LAG = '7 days'
AS (SELECT DOC_ID, TITLE, CATEGORY, ROOT_CAUSE, CONTENT FROM SEARCH.CAPACITY_DOCS);

-- ---------- Throughput gap anomaly detection (train first 75 days, detect last 15) ----------
CREATE OR REPLACE VIEW ML.THROUGHPUT_GAP_SERIES AS
SELECT ENTITY_ID, EVENT_DATE::TIMESTAMP_NTZ AS TS, THROUGHPUT_GAP_PCT::FLOAT AS THROUGHPUT_GAP
FROM RAW.LINE_DAILY;
CREATE OR REPLACE VIEW ML.THROUGHPUT_GAP_TRAIN AS
SELECT * FROM ML.THROUGHPUT_GAP_SERIES WHERE TS < (SELECT DATEADD(day, -15, MAX(TS)) FROM ML.THROUGHPUT_GAP_SERIES);
CREATE OR REPLACE VIEW ML.THROUGHPUT_GAP_DETECT AS
SELECT * FROM ML.THROUGHPUT_GAP_SERIES WHERE TS >= (SELECT DATEADD(day, -15, MAX(TS)) FROM ML.THROUGHPUT_GAP_SERIES);

CREATE OR REPLACE SNOWFLAKE.ML.ANOMALY_DETECTION ML.THROUGHPUT_GAP_ANOMALY_MODEL(
  INPUT_DATA => SYSTEM$REFERENCE('VIEW', 'ML.THROUGHPUT_GAP_TRAIN'),
  SERIES_COLNAME => 'ENTITY_ID', TIMESTAMP_COLNAME => 'TS', TARGET_COLNAME => 'THROUGHPUT_GAP',
  LABEL_COLNAME => '');

CREATE OR REPLACE TABLE ML.THROUGHPUT_GAP_ANOMALIES AS
SELECT SERIES::VARCHAR AS ENTITY_ID, TS::DATE AS EVENT_DATE, Y AS THROUGHPUT_GAP, FORECAST AS EXPECTED,
       LOWER_BOUND, UPPER_BOUND, IS_ANOMALY, PERCENTILE
FROM TABLE(ML.THROUGHPUT_GAP_ANOMALY_MODEL!DETECT_ANOMALIES(
  INPUT_DATA => SYSTEM$REFERENCE('VIEW', 'ML.THROUGHPUT_GAP_DETECT'),
  SERIES_COLNAME => 'ENTITY_ID', TIMESTAMP_COLNAME => 'TS', TARGET_COLNAME => 'THROUGHPUT_GAP'));

-- ---------- Semantic view ----------
CREATE OR REPLACE SEMANTIC VIEW APP.CAPACITY_ANALYTICS
  TABLES (
    plines AS CURATED.PERFORMANCE_SUMMARY PRIMARY KEY (ENTITY_ID)
      COMMENT = 'One row per assembly line, 90-day totals',
    risk AS ML.CONSTRAINT_RISK_SCORES PRIMARY KEY (ENTITY_ID)
      COMMENT = 'Latest next-7-day capacity constraint probability per line',
    causes AS CURATED.CONSTRAINT_CAUSES PRIMARY KEY (ROOT_CAUSE)
      COMMENT = 'Capacity constraints by root cause, 90 days',
    daily AS CURATED.TREND_ANALYSIS PRIMARY KEY (METRIC_DATE)
      COMMENT = 'Network-wide totals per day'
  )
  RELATIONSHIPS (risk_line AS risk (ENTITY_ID) REFERENCES plines)
  FACTS (
    plines.units_f AS UNITS_COMPLETED,
    plines.committed_f AS COMMITTED_UNITS,
    plines.arrivals_f AS WIP_ARRIVALS,
    plines.queue_f AS QUEUE_HOURS,
    plines.constraints_f AS CONSTRAINT_COUNT,
    plines.downtime_hours_f AS DOWNTIME_HOURS,
    plines.operating_hours_f AS OPERATING_HOURS,
    plines.planned_hours_f AS PLANNED_HOURS,
    risk.constraint_prob_f AS CONSTRAINT_PROB_7D,
    causes.cause_constraints_f AS CONSTRAINT_COUNT,
    causes.cause_shortfall_f AS UNITS_SHORTFALL,
    causes.cause_hours_f AS DOWNTIME_HOURS,
    daily.day_units_f AS UNITS_COMPLETED,
    daily.day_committed_f AS COMMITTED_UNITS,
    daily.day_constraints_f AS CONSTRAINT_COUNT
  )
  DIMENSIONS (
    plines.line_id AS ENTITY_ID WITH SYNONYMS = ('entities', 'line', 'assembly line', 'production line'),
    plines.line_name AS ENTITY_NAME,
    plines.site AS REGION WITH SYNONYMS = ('plant', 'site', 'region', 'city') COMMENT = 'Vietnamese city of the plant (fictional plants)',
    plines.line_type AS CATEGORY WITH SYNONYMS = ('line type', 'process', 'area') COMMENT = 'SMT, Through-Hole and Wave, Final Assembly, Functional Test, or Box Build and Packing',
    risk.risk_band AS RISK_BAND COMMENT = 'High >= 0.5, Medium >= 0.25, else Low',
    risk.scored_as_of AS SCORED_AS_OF,
    causes.root_cause AS ROOT_CAUSE,
    daily.metric_date AS METRIC_DATE
  )
  METRICS (
    plines.line_count AS COUNT(plines.line_id) WITH SYNONYMS = ('number of entities', 'entity count', 'number of lines'),
    plines.overall_plan_attainment_pct AS 100 * SUM(plines.units_f) / NULLIF(SUM(plines.committed_f), 0)
      COMMENT = 'Units completed / units committed in the build plan',
    plines.total_units_completed AS SUM(plines.units_f),
    plines.capacity_constraints AS SUM(plines.constraints_f) WITH SYNONYMS = ('constraints', 'capacity events', 'bottleneck events'),
    plines.avg_queue_hours_per_unit AS SUM(plines.queue_f) / NULLIF(SUM(plines.arrivals_f), 0)
      COMMENT = 'Queue hours per unit arriving at the line',
    plines.total_wip_arrivals AS SUM(plines.arrivals_f) WITH SYNONYMS = ('arrivals', 'units arriving', 'WIP'),
    plines.overall_line_availability_pct AS 100 * SUM(plines.operating_hours_f) / NULLIF(SUM(plines.planned_hours_f), 0),
    plines.total_lost_hours AS SUM(plines.downtime_hours_f),
    risk.avg_constraint_prob AS AVG(risk.constraint_prob_f),
    causes.cause_constraints AS SUM(causes.cause_constraints_f),
    causes.cause_units_shortfall AS SUM(causes.cause_shortfall_f),
    causes.cause_lost_hours AS SUM(causes.cause_hours_f),
    daily.daily_plan_attainment_pct AS 100 * SUM(daily.day_units_f) / NULLIF(SUM(daily.day_committed_f), 0),
    daily.daily_constraints AS SUM(daily.day_constraints_f)
  )
  COMMENT = 'Synthetic Vietnam electronics capacity analytics (demo)';

-- ---------- Cortex Agent ----------
CREATE OR REPLACE AGENT APP.CAPACITY_AGENT
  COMMENT = 'Capacity assistant over a synthetic network of Vietnamese electronics assembly lines'
  FROM SPECIFICATION
$$
models:
  orchestration: claude-sonnet-4-5
instructions:
  response: "Answer only from tool results. State that data is synthetic. Give line IDs and numbers with units."
  orchestration: "Use capacity_analyst for plan attainment, capacity constraints, queue hours, WIP arrivals, lines, plants, risk and root causes. Use sop_search for constraint response procedures."
tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: capacity_analyst
      description: "Plan attainment, capacity constraints, queue hours per unit, WIP arrivals, line availability, root causes and constraint-risk scores"
  - tool_spec:
      type: cortex_search
      name: sop_search
      description: "Synthetic capacity-response SOPs by line type and cause"
tool_resources:
  capacity_analyst:
    semantic_view: __DEMO_DB__.APP.CAPACITY_ANALYTICS
    execution_environment:
      type: warehouse
      warehouse: __DEMO_WH__
  sop_search:
    name: __DEMO_DB__.SEARCH.CAPACITY_SOP_SEARCH
    max_results: 3
    id_column: DOC_ID
    title_column: TITLE
$$;

-- ---------- Live-telemetry alert ----------
CREATE TABLE IF NOT EXISTS APP.ALERT_LOG (
  ALERTED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(), LINE_ID VARCHAR,
  EVENT_TS TIMESTAMP_NTZ, THROUGHPUT_GAP_PCT FLOAT, QUEUE_UNITS FLOAT, SOP_HINT VARCHAR);

CREATE OR REPLACE NOTIFICATION INTEGRATION VN_ELECTRONICS_CAPACITY_EMAIL_INT
  TYPE = EMAIL ENABLED = TRUE ALLOWED_RECIPIENTS = ('__ALERT_EMAIL__');

CREATE OR REPLACE PROCEDURE APP.LOG_LIVE_ALARMS()
RETURNS NUMBER
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
  n NUMBER;
BEGIN
  INSERT INTO APP.ALERT_LOG (LINE_ID, EVENT_TS, THROUGHPUT_GAP_PCT, QUEUE_UNITS, SOP_HINT)
    SELECT t.LINE_ID, t.EVENT_TS, t.THROUGHPUT_GAP_PCT, t.QUEUE_UNITS,
           'Check ' || tg.CATEGORY || ' SOPs; current risk band ' || COALESCE(r.RISK_BAND, 'n/a')
    FROM RAW.LIVE_TELEMETRY t
    JOIN RAW.PRODUCTION_LINES tg ON tg.ID = t.LINE_ID
    LEFT JOIN ML.CONSTRAINT_RISK_SCORES r ON r.ENTITY_ID = t.LINE_ID
    WHERE t.STATUS = 'ALARM'
      AND NOT EXISTS (SELECT 1 FROM APP.ALERT_LOG l WHERE l.LINE_ID = t.LINE_ID AND l.EVENT_TS = t.EVENT_TS);
  n := SQLROWCOUNT;
  IF (n > 0) THEN
    CALL SYSTEM$SEND_EMAIL('VN_ELECTRONICS_CAPACITY_EMAIL_INT', '__ALERT_EMAIL__',
      '[Demo] Vietnam assembly line alarm',
      'New live-telemetry alarms logged in APP.ALERT_LOG: ' || :n || '. Data is synthetic.');
  END IF;
  RETURN n;
END;
$$;

CREATE OR REPLACE ALERT APP.LIVE_ALARM_ALERT
  WAREHOUSE = __DEMO_WH__
  SCHEDULE = '5 MINUTE'
  IF (EXISTS (
    SELECT 1 FROM RAW.LIVE_TELEMETRY t
    WHERE t.STATUS = 'ALARM'
      AND NOT EXISTS (SELECT 1 FROM APP.ALERT_LOG l WHERE l.LINE_ID = t.LINE_ID AND l.EVENT_TS = t.EVENT_TS)))
  THEN CALL APP.LOG_LIVE_ALARMS();

-- ---------- On-demand refresh DAG (suspended; run with EXECUTE TASK APP.TASK_REFRESH_CURATED) ----------
CREATE OR REPLACE PROCEDURE APP.REFRESH_CURATED()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
BEGIN
  ALTER DYNAMIC TABLE CURATED.PERFORMANCE_SUMMARY REFRESH;
  ALTER DYNAMIC TABLE CURATED.TREND_ANALYSIS REFRESH;
  ALTER DYNAMIC TABLE CURATED.CONSTRAINT_CAUSES REFRESH;
  ALTER DYNAMIC TABLE CURATED.KPI_SUMMARY REFRESH;
  RETURN 'refreshed';
END;
$$;

CREATE OR REPLACE TASK APP.TASK_REFRESH_CURATED
  WAREHOUSE = __DEMO_WH__
AS
  CALL APP.REFRESH_CURATED();

CREATE OR REPLACE TASK APP.TASK_RESCORE_RISK
  WAREHOUSE = __DEMO_WH__
  AFTER APP.TASK_REFRESH_CURATED
AS
  CREATE OR REPLACE TABLE ML.CONSTRAINT_RISK_SCORES COPY GRANTS AS
  WITH latest AS (
    SELECT * FROM ML.CONSTRAINT_FEATURES QUALIFY ROW_NUMBER() OVER (PARTITION BY ENTITY_ID ORDER BY EVENT_DATE DESC) = 1
  ), p AS (
    SELECT ENTITY_ID, EVENT_DATE,
           ML.CONSTRAINT_RISK_MODEL!PREDICT(INPUT_DATA => OBJECT_CONSTRUCT(
             'CATEGORY', CATEGORY, 'AGE_YEARS', AGE_YEARS, 'THROUGHPUT_GAP_PCT', THROUGHPUT_GAP_PCT,
             'QUEUE_UNITS', QUEUE_UNITS, 'THROUGHPUT_GAP_7D', THROUGHPUT_GAP_7D, 'CONSTRAINTS_30D', CONSTRAINTS_30D)) AS PRED
    FROM latest
  )
  SELECT ENTITY_ID, EVENT_DATE AS SCORED_AS_OF, ROUND(PRED:probability:CONSTRAINED::FLOAT, 4) AS CONSTRAINT_PROB_7D,
         CASE WHEN PRED:probability:CONSTRAINED::FLOAT >= 0.5 THEN 'High'
              WHEN PRED:probability:CONSTRAINED::FLOAT >= 0.25 THEN 'Medium' ELSE 'Low' END AS RISK_BAND,
         CURRENT_TIMESTAMP() AS SCORED_AT
  FROM p;

