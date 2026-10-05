-- =====================================================================
-- 01_explore_raw.sql  |  Citibike x Weather ELT  |  run as TRANSFORMER
-- Goal: understand both sources BEFORE loading anything.
-- Nothing here loads data. Do NOT use Run All on this file:
-- run one statement at a time (click inside it, then Ctrl+Enter),
-- look at the result, and write down what you see.
-- =====================================================================

ALTER SESSION SET MULTI_STATEMENT_COUNT = 0;
USE ROLE TRANSFORMER;
USE WAREHOUSE CITIBIKE_WH;
USE DATABASE CITIBIKE_DB;
USE SCHEMA RAW;

-- ---------------------------------------------------------------------
-- A. Stages: pointers to the public S3 folders (no data copied yet)
-- ---------------------------------------------------------------------
CREATE STAGE IF NOT EXISTS RAW.CITIBIKE_TRIPS_STAGE
  URL = 's3://snowflake-workshop-lab/japan/citibike-trips/'
  COMMENT = 'Public Citibike trip files';

CREATE STAGE IF NOT EXISTS RAW.WEATHER_STAGE
  URL = 's3://snowflake-workshop-lab/weather-nyc'
  COMMENT = 'Public NYC weather JSON';

-- Check: the owner column should say TRANSFORMER for both stages.
-- If it says ACCOUNTADMIN, dbt and the load step will not be able to use them.
SHOW STAGES IN SCHEMA RAW;

-- ---------------------------------------------------------------------
-- B. What files are there?
--    Run each LIST, then the summary query straight after it.
--    The summary reads the result of the query run just before it,
--    so nothing else may run in between.
-- ---------------------------------------------------------------------
LIST @RAW.CITIBIKE_TRIPS_STAGE;

SELECT
    REGEXP_SUBSTR("name", '\\.[a-z0-9.]+$')  AS file_type,
    COUNT(*)                                 AS file_count,
    ROUND(SUM("size") / POWER(1024, 3), 2)   AS total_gb,
    MIN("name")                              AS first_file,
    MAX("name")                              AS last_file
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
GROUP BY file_type
ORDER BY file_count DESC;

LIST @RAW.WEATHER_STAGE;

SELECT
    REGEXP_SUBSTR("name", '\\.[a-z0-9.]+$')  AS file_type,
    COUNT(*)                                 AS file_count,
    ROUND(SUM("size") / POWER(1024, 3), 2)   AS total_gb,
    MIN("name")                              AS first_file,
    MAX("name")                              AS last_file
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
GROUP BY file_type
ORDER BY file_count DESC;

-- B2. Which years do the trip files cover? Reads file NAMES only, no data.
--     Run the LIST and this query together, like the pairs above.
LIST @RAW.CITIBIKE_TRIPS_STAGE;

SELECT
    REGEXP_SUBSTR("name", 'trips_([0-9]{4})', 1, 1, 'e', 1) AS trip_year,
    COUNT(*)                                               AS file_count,
    ROUND(SUM("size") / POWER(1024, 2), 1)                 AS total_mb
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
GROUP BY trip_year
ORDER BY trip_year;

-- Check the first_file and last_file paths: every file should sit inside
-- the folder you expect. The weather URL has no trailing slash, so any
-- other S3 folder whose name starts with weather-nyc would also show up.
--
-- Parquet was ruled out: reading the trip files as Parquet failed with
-- "Parquet magic bytes not found". If the file_type column shows .csv or
-- .csv.gz, use block C. If it shows anything else, stop and check.

-- ---------------------------------------------------------------------
-- C. Trips, IF the files are CSV (gz is handled automatically)
--     No header skipping on purpose: row 1 shows you the header, if any.
--     If every value lands in $1, the delimiter is not a comma.
-- ---------------------------------------------------------------------
CREATE FILE FORMAT IF NOT EXISTS RAW.CSV_PEEK_FF
  TYPE = CSV
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  COMPRESSION = AUTO;

SELECT
    METADATA$FILENAME AS file_name,
    $1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
    $11, $12, $13, $14, $15, $16
FROM @RAW.CITIBIKE_TRIPS_STAGE (FILE_FORMAT => 'RAW.CSV_PEEK_FF')
LIMIT 20;

-- ---------------------------------------------------------------------
-- D. Weather JSON
-- ---------------------------------------------------------------------
CREATE FILE FORMAT IF NOT EXISTS RAW.JSON_FF
  TYPE = JSON
  STRIP_OUTER_ARRAY = TRUE;

-- D1. A few raw records: click a cell to see the full JSON
SELECT $1
FROM @RAW.WEATHER_STAGE (FILE_FORMAT => 'RAW.JSON_FF')
LIMIT 5;

-- D2. Every field path in the JSON, with an example value
--     (samples 1,000 records so it stays cheap)
WITH weather_sample AS (
    SELECT $1 AS v
    FROM @RAW.WEATHER_STAGE (FILE_FORMAT => 'RAW.JSON_FF')
    LIMIT 1000
)
SELECT
    f.path,
    TYPEOF(f.value)      AS value_type,
    ANY_VALUE(f.value)   AS example_value,
    COUNT(*)             AS times_seen
FROM weather_sample AS s,
     LATERAL FLATTEN(INPUT => s.v, RECURSIVE => TRUE) AS f
WHERE TYPEOF(f.value) NOT IN ('OBJECT', 'ARRAY')
  AND f.path NOT LIKE 'city.langs%'   -- translations of the city name, not needed
GROUP BY f.path, TYPEOF(f.value)
ORDER BY f.path;

-- D3. Which location(s) does the weather data describe?
--     Put the lat and lon into a map: is it New York City itself?
SELECT
    $1:city.id::INT          AS city_id,
    $1:city.name::STRING     AS city_name,
    $1:city.coord.lat::FLOAT AS lat,
    $1:city.coord.lon::FLOAT AS lon,
    COUNT(*)                 AS records
FROM @RAW.WEATHER_STAGE (FILE_FORMAT => 'RAW.JSON_FF')
GROUP BY city_id, city_name, lat, lon
ORDER BY records DESC;

-- D4. Time range and temperature range per location, raw units.
--     If time is a number of seconds, first_time and last_time show it as a date.
--     Temperatures around 250 to 310 would mean Kelvin, not Celsius.
SELECT
    $1:city.id::INT                                   AS city_id,
    MIN($1:time::STRING)                              AS first_time_raw,
    MAX($1:time::STRING)                              AS last_time_raw,
    TO_TIMESTAMP(TRY_TO_NUMBER(MIN($1:time::STRING))) AS first_time,
    TO_TIMESTAMP(TRY_TO_NUMBER(MAX($1:time::STRING))) AS last_time,
    MIN(TRY_TO_DOUBLE($1:main.temp::STRING))          AS min_temp_raw,
    MAX(TRY_TO_DOUBLE($1:main.temp::STRING))          AS max_temp_raw,
    COUNT(*)                                          AS records
FROM @RAW.WEATHER_STAGE (FILE_FORMAT => 'RAW.JSON_FF')
GROUP BY city_id
ORDER BY records DESC;

-- D5. Weather condition labels and how often each appears
SELECT
    $1:city.id::INT            AS city_id,
    $1:weather[0].main::STRING AS weather_condition,
    COUNT(*)                   AS records
FROM @RAW.WEATHER_STAGE (FILE_FORMAT => 'RAW.JSON_FF')
GROUP BY city_id, weather_condition
ORDER BY city_id, records DESC;

-- D6. Across ALL records: how often is a rain or snow amount recorded,
--     compared with the Rain or Snow label? Are there duplicate times?
--     (D2 only looked at the first 1,000 records, so its counts are not
--     representative.)
SELECT
    $1:city.id::INT                                    AS city_id,
    COUNT(*)                                           AS records,
    COUNT(DISTINCT $1:time::INT)                       AS distinct_times,
    COUNT_IF($1:weather[0].main::STRING = 'Rain')      AS first_label_rain,
    COUNT_IF($1:rain IS NOT NULL)                      AS has_rain_amount,
    COUNT_IF($1:weather[0].main::STRING = 'Snow')      AS first_label_snow,
    COUNT_IF($1:snow IS NOT NULL)                      AS has_snow_amount,
    COUNT_IF(ARRAY_SIZE($1:weather) > 1)               AS several_conditions,
    -- these two also test the quoted-key path syntax before staging uses it
    MAX($1:rain."1h"::FLOAT)                           AS max_rain_1h,
    MAX($1:snow."1h"::FLOAT)                           AS max_snow_1h
FROM @RAW.WEATHER_STAGE (FILE_FORMAT => 'RAW.JSON_FF')
GROUP BY city_id
ORDER BY city_id;

-- ---------------------------------------------------------------------
-- E. Clean up (run once, after you have your answers)
--    These formats were only for exploring. The load step defines its own.
--    PARQUET_FF came from a first attempt that read the trip files as
--    Parquet; they turned out to be gzip CSV.
-- ---------------------------------------------------------------------
DROP FILE FORMAT IF EXISTS RAW.PARQUET_FF;
DROP FILE FORMAT IF EXISTS RAW.CSV_PEEK_FF;

-- ---------------------------------------------------------------------
-- F. Findings (2 Oct 2026)
--
--   TRIPS
--   1. 376 files, .csv.gz, 1.88 GB compressed, all inside japan/citibike-trips/.
--   2. Years from the file names (B2): 2013 has 56 files, 2014 to 2018 have
--      64 each. 2018 is about half the size of 2017, so 2018 is likely a
--      part year. Exact first and last trip dates: check after loading.
--   3. No header row in the two files checked (row 1 is already data).
--      The load must confirm this for every file.
--   4. 16 columns:
--      $1  trip duration in seconds
--          (checked: 11:18:09 to 11:26:24 is 8 min 15 s = 495 s)
--      $2  start time, $3 stop time (like 2013-06-09 15:07:05.000, no time zone)
--      $4  start station id, $5 name, $6 latitude, $7 longitude
--      $8  end station id,   $9 name, $10 latitude, $11 longitude
--      $12 bike id
--      $13 empty in every row checked (purpose unknown, check other years)
--      $14 user type: Customer or Subscriber
--      $15 birth year (blank for Customers)
--      $16 gender code (0, 1 or 2)
--   5. Some trips have no end station: $8 to $11 are all blank.
--   6. Some very short trips start and end at the same station (84 s).
--
--   WEATHER
--   7. 61 files, .json.gz, all inside weather-nyc/, under 0.01 GB in total.
--   8. Two locations, both named New York, with almost equal record counts:
--        5128581  lat 40.714  lon -74.006  28,962 records  New York City
--        5128638  lat 43.000  lon -75.500  28,932 records  central New York
--                 State, about 280 km north-north-west of Manhattan
--      Using the wrong one would mislead: 5128638 records Snow 3,333 times,
--      against 558 for New York City.
--   9. time is Unix epoch seconds, which is UTC by definition.
--      Range: 2016-07-05 22:31 to 2019-06-25 21:02 UTC.
--      About 27 readings per day on average, so some hours have more than
--      one reading.
--  10. main.temp for New York City ranges from 256.5 to 308.4: Kelvin
--      (about -17 C to 35 C).
--  11. Condition labels (weather[0].main) for New York City, most common first:
--      Clear 9,122  Clouds 9,034  Rain 5,742  Mist 3,161  Snow 558  Haze 483
--      Fog 326  Drizzle 321  Thunderstorm 174  Smoke 35  Squall 4  Dust 2
--
--   OVERLAP
--  12. Trips cover 2013 to 2018, weather covers July 2016 to June 2019, so
--      the analysis window starts in July 2016 and ends with the last
--      trip date (exact dates in 24).
--
--   WEATHER FIELDS (D2, first 1,000 records only, so counts are indicative)
--  13. Useful fields:
--        time                       Unix seconds (UTC)
--        main.temp, temp_min, temp_max   Kelvin
--        main.humidity              percent
--        main.pressure              hPa
--        clouds.all                 cloud cover, percent
--        wind.speed, wind.gust, wind.deg
--        rain."1h", rain."3h"       rain amount, only present in some records
--        snow."1h"                  snow amount, only present in some records
--        weather[n].main, .description, .id   condition label, detail, code
--      Units are not stated in the files. Kelvin points to OpenWeatherMap
--      standard units: hPa, percent, m/s and mm. Treat as an assumption.
--  14. A record can list several conditions at once: weather[1] in 169 of
--      1,000 records, weather[2] in 54, weather[3] in 6 (for example Rain
--      plus Mist). D5 counted weather[0] only, so it undercounts.
--  15. Numbers are stored inconsistently: main.temp is a decimal in 991
--      records and a whole number in 9. Cast every measure explicitly.
--  16. Keys that start with a digit need quotes in Snowflake paths:
--      $1:rain."1h", not $1:rain.1h
--  17. Not needed: city.langs (name translations), city.zoom, weather icons,
--      sea_level and grnd_level (only in 12 of 1,000 records).
--
--   D6 (all records, New York City location 5128581)
--  18. 28,962 records but only 21,173 distinct times: 7,789 records (27%)
--      repeat a time already seen. Staging must remove duplicates, after
--      checking whether repeats are identical copies or different readings.
--  19. 21,173 distinct times over about 26,000 hours (19.5 a day), so some
--      hours probably have no reading at all. An hourly join must expect gaps.
--  20. Rain amounts are sparse: 5,742 readings are labelled Rain first, but
--      only 2,092 readings carry a rain amount (about 36%). Snow: 558 labels,
--      300 amounts. So "rainy" and "snowy" must come from the labels, and a
--      missing amount does not mean zero.
--  21. 6,138 readings (21%) list more than one condition, more than the 17%
--      seen in the first 1,000 records.
--  22. Largest amounts: rain 32.5 mm in 1 hour (a heavy storm, plausible),
--      snow 102 mm in 1 hour (suspicious, check for outliers in staging).
--  23. The quoted-key path $1:rain."1h" works, so staging can use it.
--
--   ANSWERED AFTER LOADING (details in docs/assumptions.md)
--  24. Trips run from 1 Jun 2013 to 30 Jun 2018, so the analysis window
--      is 6 July 2016 to 30 June 2018 (decision 2). Column 13 is
--      membership_type: empty for 2013 to 2017, filled for 2018.
-- =====================================================================
