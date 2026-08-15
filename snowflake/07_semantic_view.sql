-- ============================================================================
-- 07_SEMANTIC_VIEW.SQL — Semantic View for Production Capacity Planning
-- ============================================================================
USE DATABASE ELECTRONICS_CAPACITY;
USE SCHEMA APP;

CREATE OR REPLACE SEMANTIC VIEW APP.ELECTRONICS_CAPACITY_ANALYTICS
  COMMENT = 'Electronics Manufacturing capacity planning analytics'
AS
  TABLES (
    CURATED.PERFORMANCE_DASHBOARD AS performance_dashboard,CURATED.TREND_ANALYTICS AS trend_analytics,CURATED.FORECAST_INPUT AS forecast_input,CURATED.OPERATIONAL_RISK AS operational_risk
  );
