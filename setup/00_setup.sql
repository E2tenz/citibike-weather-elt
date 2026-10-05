-- =====================================================================
-- 00_setup.sql  |  Citibike x Weather ELT  |  run once as ACCOUNTADMIN
-- Platform only: cost guardrails, compute, database, roles, dbt user.
-- Tables and models are NOT created here (RAW loads + dbt do that).
--
-- Design:
--   TRANSFORMER  builds everything in CITIBIKE_DB (you + dbt Cloud)
--   REPORTER     read-only on the database (Power BI)
--   One XSMALL warehouse, auto-suspend 60s, capped by a resource monitor
-- Run: Snowsight worksheet as ACCOUNTADMIN. Run the first line on its
-- own (Ctrl+Enter), then Run All (Ctrl+Shift+Enter).
-- =====================================================================

ALTER SESSION SET MULTI_STATEMENT_COUNT = 0;
USE ROLE ACCOUNTADMIN;

-- ---------------------------------------------------------------------
-- 1. Cost guardrail: hard stop before the trial credits are used up
-- ---------------------------------------------------------------------
CREATE RESOURCE MONITOR IF NOT EXISTS CITIBIKE_RM
  WITH CREDIT_QUOTA = 15
  TRIGGERS ON 50 PERCENT DO NOTIFY
           ON 80 PERCENT DO NOTIFY
           ON 100 PERCENT DO SUSPEND;

-- ---------------------------------------------------------------------
-- 2. Compute: one small warehouse shared by loading, dbt and Power BI
-- ---------------------------------------------------------------------
CREATE WAREHOUSE IF NOT EXISTS CITIBIKE_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  STATEMENT_TIMEOUT_IN_SECONDS = 1800
  RESOURCE_MONITOR = CITIBIKE_RM;

-- ---------------------------------------------------------------------
-- 3. Roles
-- ---------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS TRANSFORMER COMMENT = 'Loads RAW and runs dbt';
CREATE ROLE IF NOT EXISTS REPORTER    COMMENT = 'Read-only, for Power BI';

-- Role hierarchy: SYSADMIN can manage everything these roles own
GRANT ROLE TRANSFORMER TO ROLE SYSADMIN;
GRANT ROLE REPORTER    TO ROLE SYSADMIN;

GRANT USAGE ON WAREHOUSE CITIBIKE_WH TO ROLE TRANSFORMER;
GRANT USAGE ON WAREHOUSE CITIBIKE_WH TO ROLE REPORTER;

-- ---------------------------------------------------------------------
-- 3b. Give yourself both roles (before switching to TRANSFORMER below)
--     Replace Tenzo with your own Snowflake user name.
-- ---------------------------------------------------------------------
GRANT ROLE TRANSFORMER TO USER Tenzo;
GRANT ROLE REPORTER    TO USER Tenzo;

-- ---------------------------------------------------------------------
-- 4. Database and the RAW schema
--    TRANSFORMER owns the database, so dbt can create its own schemas
--    (for example STAGING and MARTS) without extra grants.
-- ---------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS CITIBIKE_DB;
GRANT OWNERSHIP ON DATABASE CITIBIKE_DB TO ROLE TRANSFORMER COPY CURRENT GRANTS;

USE ROLE TRANSFORMER;
USE WAREHOUSE CITIBIKE_WH;
CREATE SCHEMA IF NOT EXISTS CITIBIKE_DB.RAW COMMENT = 'Source data exactly as loaded from S3';

-- ---------------------------------------------------------------------
-- 5. REPORTER can read anything dbt builds now or later
-- ---------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;
GRANT USAGE  ON DATABASE CITIBIKE_DB                      TO ROLE REPORTER;
GRANT USAGE  ON FUTURE SCHEMAS IN DATABASE CITIBIKE_DB    TO ROLE REPORTER;
GRANT SELECT ON FUTURE TABLES  IN DATABASE CITIBIKE_DB    TO ROLE REPORTER;
GRANT SELECT ON FUTURE VIEWS   IN DATABASE CITIBIKE_DB    TO ROLE REPORTER;

-- ---------------------------------------------------------------------
-- 6. Service user for dbt Cloud: key-pair login only, no password
--    Generate the key pair first (Git Bash, or any terminal with openssl):
--      openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out dbt_key.p8 -nocrypt
--      openssl rsa -in dbt_key.p8 -pubout -out dbt_key.pub
--    Paste the body of dbt_key.pub below (no BEGIN/END lines, no breaks).
--    In dbt Cloud, choose Key Pair auth and paste dbt_key.p8.
--    Never commit either key file to GitHub.
-- ---------------------------------------------------------------------
CREATE USER IF NOT EXISTS DBT_CLOUD_USER
  TYPE = SERVICE
  DEFAULT_ROLE = TRANSFORMER
  DEFAULT_WAREHOUSE = CITIBIKE_WH
  COMMENT = 'dbt Cloud service user';

GRANT ROLE TRANSFORMER TO USER DBT_CLOUD_USER;

-- Run this line on its own after generating the key:
-- ALTER USER DBT_CLOUD_USER SET RSA_PUBLIC_KEY = 'MIIBIjANBgkq...';

-- ---------------------------------------------------------------------
-- 7. Checks
-- ---------------------------------------------------------------------
SHOW WAREHOUSES LIKE 'CITIBIKE_WH';
SHOW SCHEMAS IN DATABASE CITIBIKE_DB;
SHOW GRANTS TO ROLE REPORTER;