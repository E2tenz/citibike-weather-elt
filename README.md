# Citibike and weather: an ELT pipeline in Snowflake and dbt

How does the weather affect Citibike use in New York City? This repository loads public Citibike trip data and New York weather readings into Snowflake, models them with dbt, and reports the results in Power BI.

## Architecture

```mermaid
flowchart LR
    s3[("Public S3 files")] -->|"COPY INTO"| raw[("RAW")]
    raw -->|"dbt"| stg["Staging"]
    stg -->|"dbt"| int["Intermediate"]
    int -->|"dbt"| marts["Marts"]
    marts -->|"read-only role"| pbi["Power BI"]
```

| Layer | Location | Contents | Built by |
|---|---|---|---|
| Source | Public S3 bucket `snowflake-workshop-lab` | 376 gzip CSV trip files (1 Jun 2013 to 30 Jun 2018) and 61 gzip JSON weather files (5 Jul 2016 to 25 Jun 2019) | |
| RAW | `CITIBIKE_DB.RAW` | Data as received: trip values as text, weather as the original JSON, plus source file, line and load time | `setup/02_load_raw.sql` |
| Staging | `CITIBIKE_DB.STAGING` | One clean, typed row per trip and per New York City weather reading | dbt |
| Intermediate | `CITIBIKE_DB.INTERMEDIATE` | Trips and weather summed up per hour and per day | dbt |
| Marts | `CITIBIKE_DB.MARTS` | A date table plus daily and hourly tables joining trips to weather | dbt |
| Reporting | Power BI | Weather and usage report, with the marts loaded in Import mode | Power BI, signed in as `POWERBI_USER` with the read-only `REPORTER` role |

Platform choices:

- Two roles: `TRANSFORMER` loads RAW and runs dbt; `REPORTER` reads the marts and nothing else, for Power BI.
- One XSMALL warehouse that suspends after 60 seconds idle, capped by a 15-credit resource monitor.
- dbt and Power BI each connect as their own service user with key-pair authentication, so there is no password to leak, and either can be cut off without affecting the other.

## Repository

| Path | Purpose |
|---|---|
| `setup/00_setup.sql` | Snowflake platform: cost guardrail, warehouse, roles, database, dbt service user |
| `setup/01_explore_raw.sql` | Exploration of the raw files before loading, with findings |
| `setup/02_load_raw.sql` | Loads both sources into RAW, then checks the load |
| `setup/03_powerbi_access.sql` | Power BI access: limits `REPORTER` to MARTS, creates the `POWERBI_USER` service user, then checks both |
| `docs/assumptions.md` | Findings, assumptions and decisions, updated as the project goes |
| `dbt_project.yml`, `packages.yml` | dbt settings (including the analysis window) and the dbt_utils package |
| `macros/generate_schema_name.sql` | Development builds go to `DBT_DEV`; production builds go to `STAGING`, `INTERMEDIATE`, `MARTS` and `REFERENCE` |
| `seeds/` | US federal holidays, so holidays can count as weekends |
| `models/staging/` | Sources, plus one cleaned model per source |
| `models/intermediate/` | Trips and weather per hour and per day |
| `models/marts/` | `dim_date`, `fct_daily_trips_weather` and `fct_hourly_trips_weather`, which Power BI reads |
| `tests/` | Checks across models: totals reconcile, repeats are identical, closures are the known storms |

## How to rebuild

1. In Snowsight, as ACCOUNTADMIN, run `setup/00_setup.sql`: the first line on its own, then Run All.
2. Create a key pair and set the public key on `DBT_CLOUD_USER` (section 6 of `00_setup.sql`).
3. As TRANSFORMER, run `setup/02_load_raw.sql` one statement at a time, and compare each check with the expected result in its comment.
4. In dbt (v1 Latest release track), run `dbt deps`, then `dbt build`. The production job runs `dbt build` with the target name `prod`, which builds the `STAGING`, `INTERMEDIATE`, `MARTS` and `REFERENCE` schemas.
5. As ACCOUNTADMIN, run `setup/03_powerbi_access.sql` one statement at a time, and set a public key on `POWERBI_USER` (section 3). Then connect Power BI: Snowflake connector, KeyPair sign-in as `POWERBI_USER`, role `REPORTER`, Import mode.

## Status

- [x] Snowflake platform
- [x] Raw data explored and loaded: 61,468,359 trips and 57,894 weather readings, every check passed
- [x] dbt platform connected to Snowflake (key pair) and GitHub
- [x] dbt staging models: 22 tests, 0 failures, 1 expected warning
- [x] dbt intermediate models and marts: 60 tests in total, 0 failures, 1 expected warning
- [x] Production job in dbt, building the production schemas
- [x] Power BI connected to the marts: its own service user, read-only, Import mode
- [ ] Power BI report

## Highlights so far

**Results.** Compared with a typical dry day in the same month and with the same day type:

- Rain (3 or more riding hours) cuts trips by about 15%, and snow by about 30%. Four snowstorm days closed the system completely.
- Casual riders react about twice as strongly as members: -28% on rainy days and -59% on snowy days, against -14% and -28%.
- One or two wet hours make no measurable difference.
- Comparing like with like matters: a raw average says snow days have 57% fewer trips, but most of that is simply winter.

**Data findings.**

- The weather files hold two places called "New York". Only city ID 5128581 is New York City; the other is about 280 km away and records six times as much snow.
- Weather times are UTC, while trip times are New York local time, confirmed by the commuter peaks at 08:00 and 17:00.
- The 8 days with no trips at all line up with three major snowstorms.
- The weather feed is thinnest exactly when the weather is worst: on 9 Feb 2017, a blizzard day, it has only 3 readings. Days like that are measured and set aside rather than guessed.

The reasoning behind every decision is in [`docs/assumptions.md`](docs/assumptions.md).
