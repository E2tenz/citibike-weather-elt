-- =====================================================================
-- 02_load_raw.sql  |  Citibike x Weather ELT  |  run as TRANSFORMER
-- Loads both sources from S3 into RAW tables, as received.
--
-- Design:
--   RAW keeps every trip value as text and every weather record as its
--   original JSON. The only rule applied while reading is how the trip
--   files mark a missing value (an empty field or the text NULL), which
--   is read as SQL NULL. Types, filters and conversions all happen in
--   dbt staging, where every rule is visible and tested.
--   Both locations in the weather data are loaded. Filtering to New York
--   City (decision 1) happens in staging, so RAW stays a full copy.
--   Every row records which file and line it came from, and when.
--
-- Rebuild: 00_setup.sql then this file recreate the RAW layer from
-- nothing. 01_explore_raw.sql is exploration only and is not needed.
--
-- Safe to re-run: objects are only created if missing, and COPY INTO
-- remembers which files it has already loaded and skips them.
--
-- Run one statement at a time (click inside it, Ctrl+Enter) so you see
-- each result. Run All only shows the last one.
-- =====================================================================

ALTER SESSION SET MULTI_STATEMENT_COUNT = 0;
ALTER SESSION SET QUERY_TAG = 'load_raw';
USE ROLE TRANSFORMER;
USE WAREHOUSE CITIBIKE_WH;
USE DATABASE CITIBIKE_DB;
USE SCHEMA RAW;

-- ---------------------------------------------------------------------
-- 1. Where the files are and how to read them
--    The two stages and the JSON format already exist from exploration.
--    They are repeated here so this file does not depend on the
--    exploration script. IF NOT EXISTS leaves existing objects unchanged.
-- ---------------------------------------------------------------------
CREATE STAGE IF NOT EXISTS RAW.CITIBIKE_TRIPS_STAGE
  URL = 's3://snowflake-workshop-lab/japan/citibike-trips/'
  COMMENT = 'Public Citibike trip files';

CREATE STAGE IF NOT EXISTS RAW.WEATHER_STAGE
  URL = 's3://snowflake-workshop-lab/weather-nyc'
  COMMENT = 'Public NYC weather JSON';

-- Trip files: comma separated, gzip, no header row (exploration finding 3),
-- text may be wrapped in double quotes. Empty fields and the text NULL are
-- read as SQL NULL, so a missing value always looks the same in RAW.
CREATE FILE FORMAT IF NOT EXISTS RAW.TRIPS_CSV_FF
  TYPE = CSV
  FIELD_DELIMITER = ','
  SKIP_HEADER = 0
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  NULL_IF = ('NULL', 'null', '')
  EMPTY_FIELD_AS_NULL = TRUE
  COMPRESSION = AUTO
  COMMENT = 'Citibike trip files: no header, 16 columns, gzip';

-- Weather files: JSON, gzip. Same format as exploration, which gave one
-- row per weather reading.
CREATE FILE FORMAT IF NOT EXISTS RAW.JSON_FF
  TYPE = JSON
  STRIP_OUTER_ARRAY = TRUE;

-- ---------------------------------------------------------------------
-- 2. RAW tables
--    Trip columns are named from exploration (finding 4) and from the
--    column list in the public Snowflake lab for this data, which calls
--    column 13 membership_type. Check 5d showed it is empty for 2013 to
--    2017 and filled for every 2018 trip.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS RAW.TRIPS (
    trip_duration_sec        VARCHAR,
    start_time               VARCHAR,
    stop_time                VARCHAR,
    start_station_id         VARCHAR,
    start_station_name       VARCHAR,
    start_station_latitude   VARCHAR,
    start_station_longitude  VARCHAR,
    end_station_id           VARCHAR,
    end_station_name         VARCHAR,
    end_station_latitude     VARCHAR,
    end_station_longitude    VARCHAR,
    bike_id                  VARCHAR,
    membership_type          VARCHAR,
    user_type                VARCHAR,
    birth_year               VARCHAR,
    gender                   VARCHAR,
    _source_file             VARCHAR,
    _source_row              NUMBER,
    _loaded_at               TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Citibike trips as received from S3, all values as text';

CREATE TABLE IF NOT EXISTS RAW.WEATHER (
    raw_json                 VARIANT,
    _source_file             VARCHAR,
    _source_row              NUMBER,
    _loaded_at               TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
)
COMMENT = 'Weather readings as received from S3, one JSON record per row, both locations';

-- ---------------------------------------------------------------------
-- 3. Load the trips (the big one: a few minutes on XSMALL)
--    ON_ERROR = ABORT_STATEMENT: stop on the first bad row rather than
--    skip it silently. _loaded_at is filled by its column default.
--    The result lists each file with its status: expect 376 rows, all
--    LOADED. Run again later and it says 0 files processed, which is
--    fine: those files were already loaded.
-- ---------------------------------------------------------------------
COPY INTO RAW.TRIPS (
    trip_duration_sec, start_time, stop_time,
    start_station_id, start_station_name, start_station_latitude, start_station_longitude,
    end_station_id, end_station_name, end_station_latitude, end_station_longitude,
    bike_id, membership_type, user_type, birth_year, gender,
    _source_file, _source_row
)
FROM (
    SELECT
        $1, $2, $3,
        $4, $5, $6, $7,
        $8, $9, $10, $11,
        $12, $13, $14, $15, $16,
        METADATA$FILENAME,
        METADATA$FILE_ROW_NUMBER
    FROM @RAW.CITIBIKE_TRIPS_STAGE
)
FILE_FORMAT = (FORMAT_NAME = 'RAW.TRIPS_CSV_FF')
ON_ERROR = 'ABORT_STATEMENT';

-- Load summary from the load history. It can run any time within 7 days
-- of the load. TRIPS means RAW.TRIPS here (the schema set at the top).
-- Expect one row: Loaded, 376 files, rows_parsed equal to rows_loaded,
-- 0 errors.
SELECT
    status            AS load_status,
    COUNT(*)          AS file_count,
    SUM(row_parsed)   AS rows_parsed,
    SUM(row_count)    AS rows_loaded,
    SUM(error_count)  AS errors_seen
FROM TABLE(CITIBIKE_DB.INFORMATION_SCHEMA.COPY_HISTORY(
    TABLE_NAME => 'TRIPS',
    START_TIME => DATEADD(day, -7, CURRENT_TIMESTAMP())
))
GROUP BY status;

-- ---------------------------------------------------------------------
-- 4. Load the weather (small: seconds)
-- ---------------------------------------------------------------------
COPY INTO RAW.WEATHER (raw_json, _source_file, _source_row)
FROM (
    SELECT
        $1,
        METADATA$FILENAME,
        METADATA$FILE_ROW_NUMBER
    FROM @RAW.WEATHER_STAGE
)
FILE_FORMAT = (FORMAT_NAME = 'RAW.JSON_FF')
ON_ERROR = 'ABORT_STATEMENT';

-- Load summary. Expect one row: Loaded, 61 files, 57,894 rows parsed
-- and loaded (28,962 + 28,932 from exploration), 0 errors.
SELECT
    status            AS load_status,
    COUNT(*)          AS file_count,
    SUM(row_parsed)   AS rows_parsed,
    SUM(row_count)    AS rows_loaded,
    SUM(error_count)  AS errors_seen
FROM TABLE(CITIBIKE_DB.INFORMATION_SCHEMA.COPY_HISTORY(
    TABLE_NAME => 'WEATHER',
    START_TIME => DATEADD(day, -7, CURRENT_TIMESTAMP())
))
GROUP BY status;

-- ---------------------------------------------------------------------
-- 5. Checks after loading
-- ---------------------------------------------------------------------

-- 5a. Weather matches exploration: expect 28,962 rows for 5128581
--     (New York City) and 28,932 for 5128638 (New York State).
SELECT
    raw_json:city.id::INT AS city_id,
    COUNT(*)              AS row_count
FROM RAW.WEATHER
GROUP BY city_id
ORDER BY city_id;

-- 5b. Trip dates by year (answers open question 1, so it fixes the end of
--     the analysis window). days_with_trips lower than days_in_range
--     means whole days are missing from the data.
WITH trip_start AS (
    SELECT TRY_TO_TIMESTAMP_NTZ(start_time) AS start_ts
    FROM RAW.TRIPS
)

SELECT
    YEAR(start_ts)                                    AS trip_year,
    COUNT(*)                                          AS trip_count,
    MIN(start_ts)                                     AS first_start,
    MAX(start_ts)                                     AS last_start,
    COUNT(DISTINCT TO_DATE(start_ts))                 AS days_with_trips,
    DATEDIFF(day, MIN(start_ts), MAX(start_ts)) + 1   AS days_in_range
FROM trip_start
GROUP BY trip_year
ORDER BY trip_year;

-- 5c. Values that staging could not convert. A header row or a broken
--     line would show up here. Expect trip_count equal to rows_loaded in
--     step 3, 376 source files, and 0 in every bad_ column.
SELECT
    COUNT(*)                                                AS trip_count,
    COUNT(DISTINCT _source_file)                            AS source_files,
    COUNT_IF(TRY_TO_NUMBER(trip_duration_sec) IS NULL)      AS bad_duration,
    COUNT_IF(TRY_TO_TIMESTAMP_NTZ(start_time) IS NULL)      AS bad_start_time,
    COUNT_IF(TRY_TO_TIMESTAMP_NTZ(stop_time) IS NULL)       AS bad_stop_time,
    MIN(CASE WHEN TRY_TO_TIMESTAMP_NTZ(start_time) IS NULL
             THEN start_time END)                           AS bad_start_example
FROM RAW.TRIPS;

-- 5d. Did every file have the same 16-column layout? If a year had one
--     column fewer, every column after the bike ID would shift left:
--     user type would hold birth years and gender would be empty.
--     Expect 0 in both _other columns in every year. A small number of
--     missing user types or genders is a data gap, not a shift.
SELECT
    YEAR(TRY_TO_TIMESTAMP_NTZ(start_time))                  AS trip_year,
    COUNT(*)                                                AS trip_count,
    COUNT(membership_type)                                  AS membership_type_filled,
    MIN(membership_type)                                    AS membership_type_example,
    COUNT_IF(user_type IS NULL)                             AS user_type_missing,
    COUNT_IF(user_type NOT IN ('Customer', 'Subscriber'))   AS user_type_other,
    COUNT_IF(gender IS NULL)                                AS gender_missing,
    COUNT_IF(gender NOT IN ('0', '1', '2'))                 AS gender_other
FROM RAW.TRIPS
GROUP BY trip_year
ORDER BY trip_year;

-- 5e. Are trip times New York local time (assumption 1)? Local time would
--     show commuter peaks around 08:00 and 17:00 to 18:00. If the times
--     were UTC, the same peaks would appear 4 to 5 hours later.
SELECT
    HOUR(TRY_TO_TIMESTAMP_NTZ(start_time)) AS start_hour,
    COUNT(*)                               AS trip_count
FROM RAW.TRIPS
GROUP BY start_hour
ORDER BY start_hour;

-- 5f. Which days have no trips at all? 5b shows 4 such days in 2016 and
--     4 in 2017. A day with no trips could be a gap in the files, or a
--     day the system was closed, for example for a snowstorm. The daily
--     model must treat those two cases differently, so list them.
--     Each row is one gap between two days that do have trips.
--     Expect missing_days to add up to 8.
WITH trip_days AS (
    SELECT DISTINCT TO_DATE(TRY_TO_TIMESTAMP_NTZ(start_time)) AS trip_date
    FROM RAW.TRIPS
),

gaps AS (
    SELECT
        trip_date                                AS first_day_after,
        LAG(trip_date) OVER (ORDER BY trip_date) AS last_day_before
    FROM trip_days
)

SELECT
    DATEADD(day, 1, last_day_before)                    AS first_missing_day,
    DATEADD(day, -1, first_day_after)                   AS last_missing_day,
    DATEDIFF(day, last_day_before, first_day_after) - 1 AS missing_days,
    DAYNAME(DATEADD(day, 1, last_day_before))           AS first_missing_weekday
FROM gaps
WHERE DATEDIFF(day, last_day_before, first_day_after) > 1
ORDER BY first_missing_day;
