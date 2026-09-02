-- Generated from generator/demo_specs/aws-vietnam-electronics-capacity.json
-- Regenerate with: python3 generator/gen_repo_docs.py aws-vietnam-electronics-capacity
-- This is the schema that is actually deployed for VIETNAM_ELECTRONICS_CAPACITY.

-- VIETNAM_ELECTRONICS_CAPACITY  (Production Capacity Planning)
-- generated from generator/demo_specs/aws-vietnam-electronics-capacity.json - do not hand-edit
CREATE DATABASE IF NOT EXISTS VIETNAM_ELECTRONICS_CAPACITY;
CREATE SCHEMA IF NOT EXISTS VIETNAM_ELECTRONICS_CAPACITY.RAW;
CREATE SCHEMA IF NOT EXISTS VIETNAM_ELECTRONICS_CAPACITY.CURATED;
CREATE SCHEMA IF NOT EXISTS VIETNAM_ELECTRONICS_CAPACITY.APP;
USE DATABASE VIETNAM_ELECTRONICS_CAPACITY;

-- 5 real regions; entity names carry their region so the two always agree
