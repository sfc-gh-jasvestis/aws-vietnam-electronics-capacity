-- ============================================================================
-- 11_TASK_PIPELINE.SQL — Task DAG for Production Capacity Planning
-- ============================================================================
USE DATABASE ELECTRONICS_CAPACITY;
USE SCHEMA APP;

CREATE OR REPLACE TASK APP.TASK_INGEST
  WAREHOUSE = ELECTRONICS_WH
  SCHEDULE = 'USING CRON 0 */2 * * * UTC'
  COMMENT = 'Ingest latest operational data'
AS
  SELECT 1; -- Replace with actual refresh logic

CREATE OR REPLACE TASK APP.TASK_DETECT
  WAREHOUSE = ELECTRONICS_WH
  AFTER APP.TASK_INGEST
  COMMENT = 'Run anomaly detection'
AS
  SELECT 1; -- Replace with actual refresh logic

CREATE OR REPLACE TASK APP.TASK_FORECAST
  WAREHOUSE = ELECTRONICS_WH
  AFTER APP.TASK_DETECT
  COMMENT = 'Run ML.FORECAST'
AS
  SELECT 1; -- Replace with actual refresh logic

ALTER TASK APP.TASK_FORECAST RESUME;
ALTER TASK APP.TASK_DETECT RESUME;
ALTER TASK APP.TASK_INGEST RESUME;
