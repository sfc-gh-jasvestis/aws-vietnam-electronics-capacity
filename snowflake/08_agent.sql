-- ============================================================================
-- 08_AGENT.SQL — Cortex Agent for Production Capacity Planning
-- ============================================================================
USE DATABASE ELECTRONICS_CAPACITY;
USE SCHEMA APP;

CREATE OR REPLACE CORTEX AGENT APP.ELECTRONICS_CAPACITY_AGENT
  COMMENT = 'Production Capacity Planning AI Assistant'
  MODEL = 'claude-opus-4-8'
  TOOLS = (
    SEMANTIC_VIEW_TOOL(SEMANTIC_VIEW => 'ELECTRONICS_CAPACITY.APP.ELECTRONICS_CAPACITY_ANALYTICS'),    CORTEX_SEARCH_TOOL(CORTEX_SEARCH_SERVICE => 'ELECTRONICS_CAPACITY.SEARCH.ELECTRONICS_CAPACITY_SEARCH', TOOL_DESCRIPTION => 'Search documents for Electronics Manufacturing information')
  )
  SYSTEM_PROMPT = 'You are the Capacity Planning Agent for Vietnamese electronics manufacturing operations in Thai Nguyen & Hai Phong.';
