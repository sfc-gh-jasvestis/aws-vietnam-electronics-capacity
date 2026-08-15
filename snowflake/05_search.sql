-- ============================================================================
-- 05_SEARCH.SQL — Cortex Search for Production Capacity Planning
-- ============================================================================
USE DATABASE ELECTRONICS_CAPACITY;
USE SCHEMA SEARCH;

CREATE OR REPLACE CORTEX SEARCH SERVICE SEARCH.ELECTRONICS_CAPACITY_SEARCH
  ON CONTENT
  ATTRIBUTES DOC_TYPE, CATEGORY
  WAREHOUSE = ELECTRONICS_WH
  TARGET_LAG = '1 hour'
AS (
  SELECT * FROM RAW.DOCUMENTS
);
