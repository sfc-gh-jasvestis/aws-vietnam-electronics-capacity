-- Synthetic line-day observations for electronics assembly lines (SMT, wave,
-- final assembly, functional test, box build). Nothing is seeded as a
-- prediction. Randomness is HASH-seeded, so every rebuild is reproducible:
-- per-line age and constraint propensity, wear between PM windows, missed PM,
-- a committed build plan that tightens over the window, category-weighted
-- constraint causes, and two site-wide grid power dips. Plants, lines and
-- customers are fictional; the cities are real Vietnamese cities.
USE DATABASE IDENTIFIER($DEMO_DB);
USE SCHEMA RAW;
USE WAREHOUSE IDENTIFIER($DEMO_WH);

CREATE TABLE RAW.PRODUCTION_LINES AS
WITH line_seq AS (
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS LINE_INDEX
  FROM TABLE(GENERATOR(ROWCOUNT => 28))
), draws AS (
  SELECT LINE_INDEX,
         MOD(ABS(HASH(LINE_INDEX, 'vnelc-cap-age')), 1000000) / 1e6 AS U_AGE,
         MOD(ABS(HASH(LINE_INDEX, 'vnelc-cap-rate')), 1000000) / 1e6 AS U_RATE,
         MOD(ABS(HASH(LINE_INDEX, 'vnelc-cap-pm')), 1000000) / 1e6 AS U_PM,
         MOD(ABS(HASH(LINE_INDEX, 'vnelc-cap-discipline')), 1000000) / 1e6 AS U_DISCIPLINE,
         MOD(ABS(HASH(LINE_INDEX, 'vnelc-cap-throughput')), 1000000) / 1e6 AS U_THROUGHPUT
  FROM line_seq
)
SELECT 'LN-' || LPAD(LINE_INDEX::VARCHAR, 4, '0') AS ID,
       'Synthetic assembly line ' || LPAD(LINE_INDEX::VARCHAR, 4, '0') AS NAME,
       -- Deterministic spread (7 and 5 are coprime): every city and line type is present.
       CASE MOD(LINE_INDEX, 7) WHEN 0 THEN 'Bac Ninh' WHEN 1 THEN 'Bac Ninh'
            WHEN 2 THEN 'Bac Giang' WHEN 3 THEN 'Bac Giang' WHEN 4 THEN 'Hai Phong'
            WHEN 5 THEN 'Thai Nguyen' ELSE 'Bien Hoa' END AS REGION,
       CASE MOD(LINE_INDEX, 5) WHEN 0 THEN 'SMT' WHEN 1 THEN 'Through-Hole and Wave'
            WHEN 2 THEN 'Final Assembly' WHEN 3 THEN 'Functional Test'
            ELSE 'Box Build and Packing' END AS CATEGORY,
       LINE_INDEX,
       ROUND(1 + U_AGE * 14, 1) AS AGE_YEARS,
       -- Base daily constraint probability 0.9%-4.3%; ~16% of lines are chronic (x3).
       (0.009 + U_RATE * 0.034) * IFF(U_RATE > 0.84, 3, 1) AS BASE_CONSTRAINT_RATE,
       7 * (1 + FLOOR(U_PM * 3)) AS PM_INTERVAL_DAYS,
       0.60 + U_DISCIPLINE * 0.38 AS PM_COMPLETION_PROB,
       -- Qualified units per hour for the whole line.
       ROUND(CASE MOD(LINE_INDEX, 5) WHEN 0 THEN 140 + U_THROUGHPUT * 60
                  WHEN 1 THEN 90 + U_THROUGHPUT * 40 WHEN 2 THEN 70 + U_THROUGHPUT * 35
                  WHEN 3 THEN 55 + U_THROUGHPUT * 30 ELSE 160 + U_THROUGHPUT * 80 END, 1)
         AS QUALIFIED_UNITS_PER_HOUR,
       'Active' AS STATUS
FROM draws;

CREATE TABLE RAW.LINE_DAILY AS
WITH days AS (
  SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS DAY_INDEX
  FROM TABLE(GENERATOR(ROWCOUNT => 90))
), power_dips AS (
  -- Two site-wide grid power dips in the window.
  SELECT * FROM VALUES (27, 'Bac Ninh', 2.5), (63, 'Hai Phong', 3.0) AS o(DAY_INDEX, REGION, HOURS)
), base AS (
  SELECT l.ID AS ENTITY_ID, l.LINE_INDEX, l.CATEGORY, l.REGION, l.AGE_YEARS,
         l.BASE_CONSTRAINT_RATE, l.PM_INTERVAL_DAYS, l.PM_COMPLETION_PROB, l.QUALIFIED_UNITS_PER_HOUR,
         d.DAY_INDEX,
         DATEADD('day', d.DAY_INDEX - 89, CURRENT_DATE()) AS EVENT_DATE,
         22.0 AS PLANNED_HOURS,
         MOD(d.DAY_INDEX + l.LINE_INDEX * 3, l.PM_INTERVAL_DAYS) AS DAYS_SINCE_PM,
         MOD(ABS(HASH(l.ID, d.DAY_INDEX, 'vnelc-cap-event')), 1000000) / 1e6 AS U_CONSTRAINT,
         MOD(ABS(HASH(l.ID, d.DAY_INDEX, 'vnelc-cap-down')), 1000000) / 1e6 + 1e-6 AS U_DOWN,
         MOD(ABS(HASH(l.ID, d.DAY_INDEX, 'vnelc-cap-cause')), 1000000) / 1e6 AS U_CAUSE,
         MOD(ABS(HASH(l.ID, d.DAY_INDEX, 'vnelc-cap-pmdone')), 1000000) / 1e6 AS U_PMDONE,
         MOD(ABS(HASH(l.ID, d.DAY_INDEX, 'vnelc-cap-load')), 1000000) / 1e6 AS U_LOAD,
         MOD(ABS(HASH(l.ID, d.DAY_INDEX, 'vnelc-cap-noise')), 1000000) / 1e6 AS U_NOISE,
         MOD(ABS(HASH(l.ID, d.DAY_INDEX, 'vnelc-cap-hit')), 1000000) / 1e6 AS U_HIT,
         p.HOURS AS DIP_HOURS
  FROM RAW.PRODUCTION_LINES l CROSS JOIN days d
  LEFT JOIN power_dips p ON p.DAY_INDEX = d.DAY_INDEX AND p.REGION = l.REGION
), pm AS (
  SELECT *,
         IFF(DAYS_SINCE_PM = 0, 1, 0) AS PM_DUE,
         IFF(DAYS_SINCE_PM = 0 AND U_PMDONE < PM_COMPLETION_PROB, 1, 0) AS PM_COMPLETED,
         -- Wear (nozzles, fixtures, solder pot) rises between PM windows; weak discipline carries it over.
         DAYS_SINCE_PM / PM_INTERVAL_DAYS + (1 - PM_COMPLETION_PROB) AS WEAR,
         -- Committed loading tightens from about 83% to 100% of qualified capacity over the window.
         0.83 + 0.12 * DAY_INDEX / 89 + 0.05 * U_LOAD AS LOADING
  FROM base
), events AS (
  SELECT *,
         CASE WHEN DIP_HOURS IS NOT NULL THEN 1
              WHEN U_CONSTRAINT < LEAST(0.5, BASE_CONSTRAINT_RATE * (0.4 + 1.6 * WEAR) * (1 + AGE_YEARS / 25)) / 4 THEN 2
              WHEN U_CONSTRAINT < LEAST(0.5, BASE_CONSTRAINT_RATE * (0.4 + 1.6 * WEAR) * (1 + AGE_YEARS / 25)) THEN 1
              ELSE 0 END AS CONSTRAINT_COUNT
  FROM pm
), timed AS (
  SELECT *,
         -- Lost line hours: exponential, mean depends on the line type.
         CASE WHEN CONSTRAINT_COUNT = 0 THEN 0.0
              WHEN DIP_HOURS IS NOT NULL THEN DIP_HOURS
              ELSE LEAST(16.0, ROUND(CONSTRAINT_COUNT * (0.5 - LN(U_DOWN) *
                   CASE CATEGORY WHEN 'SMT' THEN 3.6 WHEN 'Through-Hole and Wave' THEN 3.0
                                 WHEN 'Final Assembly' THEN 2.4 WHEN 'Functional Test' THEN 2.8 ELSE 1.8 END), 1))
         END AS DOWNTIME_HOURS
  FROM events
), output AS (
  SELECT *,
         PLANNED_HOURS - DOWNTIME_HOURS AS OPERATING_HOURS,
         ROUND(PLANNED_HOURS * QUALIFIED_UNITS_PER_HOUR * LOADING) AS COMMITTED,
         -- Running efficiency versus the qualified rate: minus wear, age and the constraint hit.
         LEAST(0.995, GREATEST(0.55, 0.98 - 0.032 * WEAR - 0.006 * AGE_YEARS / 15 - 0.009 * U_NOISE
           - CONSTRAINT_COUNT * (0.05 + 0.07 * U_HIT))) AS EFFICIENCY,
         -- Queue hours per unit by line type; wear and constraints add waiting.
         CASE CATEGORY WHEN 'SMT' THEN 0.9 WHEN 'Through-Hole and Wave' THEN 0.7
                       WHEN 'Final Assembly' THEN 0.6 WHEN 'Functional Test' THEN 1.3 ELSE 0.4 END
           * (1 + 0.25 * WEAR + 0.40 * CONSTRAINT_COUNT + 0.10 * U_NOISE) AS QH_PER_UNIT
  FROM timed
)
SELECT ENTITY_ID || '-' || TO_CHAR(EVENT_DATE, 'YYYYMMDD') AS EVENT_ID,
       ENTITY_ID, EVENT_DATE, PLANNED_HOURS, DOWNTIME_HOURS, OPERATING_HOURS,
       CONSTRAINT_COUNT,
       CASE WHEN CONSTRAINT_COUNT = 0 THEN 'None'
            WHEN DIP_HOURS IS NOT NULL THEN 'Grid power dip'
            WHEN CATEGORY = 'SMT' THEN IFF(U_CAUSE < 0.45, 'Feeder setup overrun', IFF(U_CAUSE < 0.8, 'Component shortage', 'Placement head down'))
            WHEN CATEGORY = 'Through-Hole and Wave' THEN IFF(U_CAUSE < 0.55, 'Wave solder pot down', 'Fixture changeover overrun')
            WHEN CATEGORY = 'Final Assembly' THEN IFF(U_CAUSE < 0.5, 'Operator shortage', IFF(U_CAUSE < 0.8, 'Screwdriving station down', 'Hot-order preemption'))
            WHEN CATEGORY = 'Functional Test' THEN IFF(U_CAUSE < 0.5, 'Test fixture failure', IFF(U_CAUSE < 0.8, 'Retest backlog', 'Test program requalification'))
            ELSE IFF(U_CAUSE < 0.6, 'Packaging material shortage', 'Label printer down') END AS ROOT_CAUSE,
       PM_DUE, PM_COMPLETED,
       -- Units released into the line queue, close to the committed plan.
       ROUND(COMMITTED * (0.97 + 0.06 * U_NOISE)) AS WIP_ARRIVALS,
       COMMITTED AS COMMITTED_UNITS,
       LEAST(COMMITTED, ROUND(OPERATING_HOURS * QUALIFIED_UNITS_PER_HOUR * EFFICIENCY)) AS UNITS_COMPLETED,
       ROUND(COMMITTED * QH_PER_UNIT + DOWNTIME_HOURS * QUALIFIED_UNITS_PER_HOUR * 0.5, 1) AS QUEUE_HOURS,
       ROUND(0.9 + 2.4 * WEAR + 3.4 * CONSTRAINT_COUNT + U_NOISE * 0.8, 2) AS THROUGHPUT_GAP_PCT,
       ROUND(220 + 50 * WEAR + 42 * CONSTRAINT_COUNT + U_NOISE * 15, 1) AS QUEUE_UNITS,
       CURRENT_TIMESTAMP() AS LOADED_AT
FROM output;

-- Backup station qualification per line (snapshot): stations needed to build
-- the line critical product family with one station down, versus stations
-- qualified today and stations in qualification.
CREATE TABLE RAW.LINE_QUALIFICATION AS
SELECT ID AS ENTITY_ID,
       CASE CATEGORY WHEN 'SMT' THEN 'Smartphone mainboard' WHEN 'Through-Hole and Wave' THEN 'Power supply board'
                     WHEN 'Final Assembly' THEN 'Wearable device' WHEN 'Functional Test' THEN 'Camera module'
                     ELSE 'Router and gateway' END AS PRODUCT_FAMILY,
       2 + MOD(ABS(HASH(ID, 'vnelc-cap-req')), 3) AS REQUIRED_STATIONS,
       MOD(ABS(HASH(ID, 'vnelc-cap-qual')), 5) AS QUALIFIED_STATIONS,
       IFF(MOD(ABS(HASH(ID, 'vnelc-cap-qual')), 5) < 2 + MOD(ABS(HASH(ID, 'vnelc-cap-req')), 3),
           MOD(ABS(HASH(ID, 'vnelc-cap-inqual')), 3), 0) AS IN_QUALIFICATION,
       CURRENT_DATE() AS SNAPSHOT_DATE
FROM RAW.PRODUCTION_LINES;
