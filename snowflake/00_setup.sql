-- ============================================================================
-- Production Capacity Planning
-- Production Capacity Planning for Vietnam - ML.FORECAST and Dynamic Tables power real-time capacity planning intelligence for electronics manufacturing in Thai Nguyen & Hai Phong.
-- ============================================================================
USE ROLE ACCOUNTADMIN;
CREATE DATABASE IF NOT EXISTS ELECTRONICS_CAPACITY;
CREATE WAREHOUSE IF NOT EXISTS ELECTRONICS_WH WAREHOUSE_SIZE = 'MEDIUM' AUTO_SUSPEND = 120 AUTO_RESUME = TRUE;
USE DATABASE ELECTRONICS_CAPACITY;
CREATE SCHEMA IF NOT EXISTS RAW;
CREATE SCHEMA IF NOT EXISTS CURATED;
CREATE SCHEMA IF NOT EXISTS ML;
CREATE SCHEMA IF NOT EXISTS AI;
CREATE SCHEMA IF NOT EXISTS SEARCH;
CREATE SCHEMA IF NOT EXISTS APP;

USE WAREHOUSE ELECTRONICS_WH;
