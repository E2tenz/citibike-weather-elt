-- =====================================================================
-- 03_powerbi_access.sql  |  Citibike x Weather ELT  |  run as ACCOUNTADMIN
-- Read access for Power BI, limited to the MARTS schema.
--
-- Design:
--   REPORTER reads MARTS and nothing else (least privilege). Until now
--   it could read every schema dbt creates; those database-wide grants
--   are replaced here by grants on MARTS only.
--   POWERBI_USER is a service user with key-pair login, like the dbt
--   user: no password, and REPORTER is the only role it holds.
--
-- Run after the first production dbt run, so the MARTS schema exists.
-- Run one statement at a time (click inside it, Ctrl+Enter).
-- =====================================================================

ALTER SESSION SET MULTI_STATEMENT_COUNT = 0;
USE ROLE ACCOUNTADMIN;

-- ---------------------------------------------------------------------
-- 1. Stop REPORTER reading every new schema and table in the database
-- ---------------------------------------------------------------------
REVOKE USAGE ON FUTURE SCHEMAS IN DATABASE CITIBIKE_DB FROM ROLE REPORTER;
REVOKE SELECT ON FUTURE TABLES IN DATABASE CITIBIKE_DB FROM ROLE REPORTER;
REVOKE SELECT ON FUTURE VIEWS IN DATABASE CITIBIKE_DB FROM ROLE REPORTER;

-- Remove the access it already has to schemas other than MARTS
REVOKE USAGE ON SCHEMA CITIBIKE_DB.DBT_DEV FROM ROLE REPORTER;
REVOKE USAGE ON SCHEMA CITIBIKE_DB.STAGING FROM ROLE REPORTER;
REVOKE USAGE ON SCHEMA CITIBIKE_DB.INTERMEDIATE FROM ROLE REPORTER;
REVOKE USAGE ON SCHEMA CITIBIKE_DB.REFERENCE FROM ROLE REPORTER;

-- ---------------------------------------------------------------------
-- 2. Read access to MARTS only, including tables dbt rebuilds later
-- ---------------------------------------------------------------------
GRANT USAGE ON SCHEMA CITIBIKE_DB.MARTS TO ROLE REPORTER;
GRANT SELECT ON ALL TABLES IN SCHEMA CITIBIKE_DB.MARTS TO ROLE REPORTER;
GRANT SELECT ON FUTURE TABLES IN SCHEMA CITIBIKE_DB.MARTS TO ROLE REPORTER;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA CITIBIKE_DB.MARTS TO ROLE REPORTER;

-- ---------------------------------------------------------------------
-- 3. Service user for Power BI: key-pair login only, read-only role
-- ---------------------------------------------------------------------
CREATE USER IF NOT EXISTS POWERBI_USER
  TYPE = SERVICE
  DEFAULT_ROLE = REPORTER
  DEFAULT_WAREHOUSE = CITIBIKE_WH
  COMMENT = 'Power BI report, reads MARTS only';

GRANT ROLE REPORTER TO USER POWERBI_USER;

-- Key pair, made in Git Bash on the computer that runs Power BI. The
-- last line puts the finished ALTER USER statement on the clipboard,
-- so the public key is never copied by hand:
--   mkdir -p ~/keys/citibike
--   openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out ~/keys/citibike/powerbi_key.p8 -nocrypt
--   openssl rsa -in ~/keys/citibike/powerbi_key.p8 -pubout -out ~/keys/citibike/powerbi_key.pub
--   PUB=$(grep -v "PUBLIC KEY" ~/keys/citibike/powerbi_key.pub | tr -d '\r\n')
--   echo "ALTER USER POWERBI_USER SET RSA_PUBLIC_KEY = '$PUB';" | /c/Windows/System32/clip.exe
-- Paste the statement here and run it on its own, then check the
-- fingerprint in section 4. In Power BI: Snowflake connector, KeyPair,
-- user POWERBI_USER, the whole of powerbi_key.p8 pasted into Private Key
-- (BEGIN and END lines included), no passphrase, Import mode.
-- Never commit either key file.
-- ALTER USER POWERBI_USER SET RSA_PUBLIC_KEY = 'MIIBIjANBgkq...';

-- A second computer gets its own key in the second slot, so either key
-- can be removed without affecting the other:
-- ALTER USER POWERBI_USER SET RSA_PUBLIC_KEY_2 = 'MIIBIjANBgkq...';
-- ALTER USER POWERBI_USER UNSET RSA_PUBLIC_KEY_2;

-- ---------------------------------------------------------------------
-- 4. Checks
-- ---------------------------------------------------------------------
SHOW GRANTS TO ROLE REPORTER;

-- The key in Snowflake must belong to the private key Power BI uses.
-- RSA_PUBLIC_KEY_FP (or RSA_PUBLIC_KEY_2_FP) must equal "SHA256:" plus
-- the output of this Git Bash command:
--   openssl rsa -pubin -in ~/keys/citibike/powerbi_key.pub -outform DER | openssl dgst -sha256 -binary | openssl enc -base64
DESC USER POWERBI_USER;

-- If Power BI cannot sign in, it only says the credentials failed.
-- Snowflake records the reason, for example
-- JWT_TOKEN_INVALID_PUBLIC_KEY_FINGERPRINT_MISMATCH (the keys do not match).
SELECT event_timestamp, is_success, error_code, error_message
FROM TABLE(CITIBIKE_DB.INFORMATION_SCHEMA.LOGIN_HISTORY_BY_USER(
    USER_NAME => 'POWERBI_USER', RESULT_LIMIT => 10))
ORDER BY event_timestamp DESC;

-- Secondary roles are switched off first: otherwise Snowsight also
-- uses your other roles (such as TRANSFORMER), and both checks below
-- would pass whatever REPORTER itself is allowed to do.
USE ROLE REPORTER;
USE SECONDARY ROLES NONE;

-- REPORTER can read MARTS: expect 725
SELECT COUNT(*) AS days FROM CITIBIKE_DB.MARTS.FCT_DAILY_TRIPS_WEATHER;

-- REPORTER cannot read anything else: expect an error saying the table
-- does not exist or is not authorized. Here, the error means it worked.
SELECT COUNT(*) AS trips FROM CITIBIKE_DB.STAGING.STG_CITIBIKE__TRIPS;

-- Back to normal for the rest of the session
USE SECONDARY ROLES ALL;
