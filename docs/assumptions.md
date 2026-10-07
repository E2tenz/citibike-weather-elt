# Assumptions and decisions

A running log of what I found in the data, what I assumed, and why.
Updated as the project goes.

## Source data (explored 2 Oct 2026)

| Source | Location | Format | Size | Coverage |
|---|---|---|---|---|
| Citibike trips | `s3://snowflake-workshop-lab/japan/citibike-trips/` | 376 CSV files, gzip, no header row | 1.88 GB compressed | 1 Jun 2013 to 30 Jun 2018 (2018 is January to June only) |
| NYC weather | `s3://snowflake-workshop-lab/weather-nyc` | 61 JSON files, gzip | under 0.01 GB | 5 Jul 2016 to 25 Jun 2019 |

## Where this data comes from, and where I differ

The files sit in Snowflake's public `snowflake-workshop-lab` bucket, which older versions of Snowflake's "Zero to Snowflake" hands-on lab use. Published copies of that lab's SQL ([lab scripts](https://github.com/woutertrappers/zero-to-snowflake/blob/master/lab_scripts_InpersonZTS.sql), [Hashmap's version](https://gist.github.com/randypitcherii/720dc5003c8a30c217ebd641b5bfc578)) use the same weather path, `weather-nyc`, and show:

- **Column 13 of the trip files is called `membership_type`.** I use that name. It is empty for 2013 to 2017 and filled for every 2018 trip.
- **The weather is filtered to city ID 5128638.** My exploration shows that this is the central New York State location, about 280 km from Manhattan, with six times the snow. I use 5128581, New York City (decision 1).
- **Only the first weather condition, `weather[0]`, is used.** 21% of readings list more than one condition, so I check all of them (decision 8).
- **Weather is joined to trips by hour without converting UTC to New York time.** That puts every match 4 to 5 hours out, so I convert first (decision 3).

The lab was written to teach Snowflake features, not to analyse weather, so these shortcuts made sense there. I treat it as a useful reference, not as ground truth.

## What I found

**Trips**
- 16 columns: trip duration (seconds), start and stop time, start and end station (ID, name, latitude, longitude), bike ID, membership type (column 13: empty for 2013 to 2017, filled for 2018), user type (Customer or Subscriber), birth year and a gender code.
- Trip duration checked on one trip: start 11:18:09, stop 11:26:24 is 8 min 15 s = 495 s, matching column 1.
- Some trips have no end station (ID, name and coordinates all blank).
- Some very short trips start and end at the same station (84 seconds).
- Timestamps have no time zone.
- Citibike's own description of the data ([System Data page](https://citibikenyc.com/system-data)): a Customer has a 24-hour or 3-day pass and a Subscriber is an annual member. Before publishing, Citibike removes trips taken by staff, trips to or from test stations, and trips under 60 seconds.

**Weather**
- The files hold two locations, both called "New York", with almost the same number of records:

  | City ID | Latitude | Longitude | Records | Where it is |
  |---|---|---|---|---|
  | 5128581 | 40.714 | -74.006 | 28,962 | New York City |
  | 5128638 | 43.000 | -75.500 | 28,932 | Central New York State, about 280 km north-north-west of Manhattan |

- They are not interchangeable: the State location records "Snow" 3,333 times, the City only 558 times, about six times more.
- Time is stored as Unix seconds, which is UTC.
- About 27 readings a day on average, so some hours have more than one reading.
- Temperature is in Kelvin: 256.5 to 308.4 for New York City, about -17 C to 35 C.
- 12 weather condition labels. For New York City, most common first: Clear, Clouds, Rain, Mist, Snow, Haze, Fog, Drizzle, Thunderstorm, Smoke, Squall, Dust.
- A record can list several conditions at once (for example Rain plus Mist). In the first 1,000 records, 17% had a second condition and a few had up to four. Counting only the first condition undercounts rain and snow.
- Useful fields (from the first 1,000 records, so counts are indicative):

  | Field | Meaning | Unit (assumed) |
  |---|---|---|
  | `time` | Time of the reading | Unix seconds, UTC |
  | `main.temp`, `temp_min`, `temp_max` | Temperature | Kelvin |
  | `main.humidity` | Humidity | % |
  | `main.pressure` | Air pressure | hPa |
  | `clouds.all` | Cloud cover | % |
  | `wind.speed`, `wind.gust`, `wind.deg` | Wind | m/s, degrees |
  | `rain."1h"`, `rain."3h"` | Rain in the last 1 or 3 hours, only in some records | mm |
  | `snow."1h"` | Snow in the last hour, only in some records | mm |
  | `weather[n].main`, `.description`, `.id` | Condition label, detail, code | |

- The files do not state units. Kelvin temperatures point to OpenWeatherMap's standard units (hPa, %, m/s, mm), so I treat those as an assumption.
- Numbers are stored inconsistently: `main.temp` is a decimal in most records but a whole number in a few. Every measure needs an explicit type conversion.
- Not needed: translations of the city name, map zoom, weather icons, and two rarely filled pressure fields.

**Weather quality, checked across all records (New York City location)**
- 28,962 readings but only 21,173 distinct times: 27% of readings repeat a time already seen.
- 21,173 distinct times over about 26,000 hours, so some hours probably have no reading at all.
- Rain amounts are sparse: 5,742 readings are labelled Rain first, but only 2,092 carry a rain amount (36%). For snow it is 558 labels and 300 amounts. A missing amount does not mean it was dry.
- 21% of readings list more than one condition.
- The largest snow amount is 102 mm in one hour, which looks suspicious. The largest rain amount, 32.5 mm in one hour, is plausible for a heavy storm.

## Load results (2 Oct 2026, `02_load_raw.sql`)

Every check passed. Both loads read every row of every file without a single error.

| Check | Result |
|---|---|
| Trips load | 376 files, 61,468,359 rows parsed and loaded, 0 errors |
| Weather load | 61 files, 57,894 rows parsed and loaded, 0 errors |
| Weather by location (5a) | 28,962 rows for 5128581 and 28,932 for 5128638, the same as exploration |
| Values that will not convert (5c) | 0 bad durations, 0 bad start times, 0 bad stop times |
| Column layout (5d) | The same layout in every year: user type is always Customer or Subscriber when filled, and gender is always 0, 1 or 2 |

**Trips by year (checks 5b and 5d)**

| Year | Trips | First trip | Last trip | Days with trips | Trips with no user type |
|---|---|---|---|---|---|
| 2013 | 5,614,888 | 1 Jun | 31 Dec | 214 of 214 | 0 |
| 2014 | 8,081,216 | 1 Jan | 31 Dec | 365 of 365 | 0 |
| 2015 | 9,937,969 | 1 Jan | 31 Dec | 365 of 365 | 0 |
| 2016 | 13,845,655 | 1 Jan | 31 Dec | 362 of 366 | 35,871 (0.26%) |
| 2017 | 16,364,657 | 1 Jan | 31 Dec | 361 of 365 | 15,909 (0.10%) |
| 2018 | 7,623,974 | 1 Jan | 30 Jun | 181 of 181 | 0 |

- Trips run from 1 Jun 2013 to 30 Jun 2018. 2018 covers January to June only.
- **8 days have no trips at all, and every gap starts on the day of a major snowstorm** (check 5f):

| Days with no trips | Days | Storm | In the analysis window? |
|---|---|---|---|
| Sat 23 to Tue 26 Jan 2016 | 4 | Blizzard of 22 to 24 Jan 2016: 27.5 inches (70 cm) in Central Park, the most since records began in 1869 | No, it is before the weather data starts |
| Thu 9 Feb 2017 | 1 | Blizzard of 9 Feb 2017: 9.4 inches (24 cm) in Central Park | Yes |
| Tue 14 to Thu 16 Mar 2017 | 3 | Winter Storm Stella, 14 to 15 Mar 2017: the city escaped the worst of it, but officials still called conditions dangerous | Yes |

So these are almost certainly days the system was closed for snow, not gaps in the files. Storm details: National Weather Service summaries for [January 2016](https://www.weather.gov/okx/Blizzard_Jan2016) and [February 2017](https://www.weather.gov/okx/Blizzard_Feb92017), and [weather.com on Stella](https://weather.com/storms/winter/news/new-york-snow-winter-storm-stella).
- Membership type is empty for 2013 to 2017 and filled for every 2018 trip, with plan names such as "$25 Off Annual Membership".
- 51,780 trips in 2016 and 2017 have no user type.
- Usage grows fast: 2016 had 39% more trips than 2015, and 2017 had 18% more than 2016.

**Trips by start hour (check 5e)**

Every start time converts to a timestamp, so every trip falls in one of the 24 hours.

| Hour | Trips | Share |
|---|---|---|
| 08:00 (morning peak) | 4,860,267 | 7.9% |
| 17:00 (evening peak) | 6,048,614 | 9.8% |
| 18:00 | 5,790,387 | 9.4% |
| 04:00 (quietest) | 108,641 | 0.2% |

07:00 to 09:59 holds 18.7% of all trips, and 16:00 to 18:59 holds 26.4%. The busiest hour has 56 times the trips of the quietest.

## Staging results (6 Oct 2026, first `dbt build`)

24 nodes (2 models and 22 tests): 23 passed, 1 warned, 0 failed.

- All 61,468,359 trips came through staging, the same count as RAW.
- **Repeated weather readings are exact copies.** The test comparing every repeat passed, so keeping one reading per time loses nothing.
- User type is only Subscriber, Customer or Unknown, and the weather labels are only the 12 known ones.
- **The large snow amounts do not affect the analysis.** The warning flagged 9 readings above 50 mm. Every snow amount above 20 mm (22 readings) falls between November 2018 and March 2019, after the analysis window ends. The values also come in half-inch steps: 25, 38, 51, 63.5, 76 and 102 mm are 1, 1.5, 2, 2.5, 3 and 4 inches. That looks like snow depth in inches, not snowfall per hour. Snow is decided from labels (decision 10), so these amounts are never used.
- **Our weather data confirms Stella, but not the 9 Feb 2017 blizzard.** Readings around the closures:

| Date | Readings | With snow | Temperature range |
|---|---|---|---|
| 8 Feb 2017 | 4 | 0 | 5.3 to 12.6 C |
| 9 Feb 2017 (closed) | 3 | 0 | -6.7 to 0.7 C |
| 10 Feb 2017 | 4 | 0 | -6.1 to -0.8 C |
| 13 Mar 2017 | 6 | 3 | -7.3 to 0.7 C |
| 14 Mar 2017 (closed) | 6 | 5 | -4.5 to -1.2 C |
| 15 Mar 2017 (closed) | 5 | 4 | -6.6 to -3.9 C |
| 16 Mar 2017 (closed) | 15 | 1 | -4.4 to 3.9 C |
| 17 Mar 2017 | 23 | 0 | -2.4 to 7.6 C |

An average day has about 20 readings; around both storms there are only 3 to 6. The weather data is thinnest exactly when the weather is worst. On 9 Feb it shows the temperature falling about 12 degrees, but not a single snow label. This is why the daily model measures how many hours each day are covered, and sets aside days without enough readings (decision 27).

## Marts results (6 Oct 2026, full `dbt build`)

70 nodes (9 models, 1 seed and 60 tests): 69 passed, 1 warned (the known snow amounts), 0 failed. The reconciliation tests confirm that the daily table counts every trip in the window exactly once, the hourly table adds up to the daily one, and the only closed days are the four storm days.

**First answer: how weather changes trips** (median change against a typical dry day in the same month, year and day type; 721 open days)

| Day's weather | Days | All trips | Members | Casual riders |
|---|---|---|---|---|
| Dry | 205 | baseline | baseline | baseline |
| Light rain (1 to 2 riding hours) | 67 | -0.2% | +0.3% | +4.8% |
| Rain (3 or more riding hours) | 164 | -14.5% | -13.6% | -27.5% |
| Snow | 43 | -30.1% | -27.8% | -58.6% |
| Not enough weather data | 242 | not compared | | |

- Rain cuts trips by about 15% and snow by about 30%. On the 4 closure days in the window, snow cut them by 100%.
- Casual riders react about twice as strongly as members, to both rain and snow.
- One or two wet hours make no measurable difference.
- **Comparing like with like matters.** Raw averages say snow days have 57% fewer trips than dry days and light-rain days 6% more. Most of that is season: snow falls in winter, when few people ride anyway, and showers fall mostly in summer. Against the same month and day type, snow costs about 30% and light rain nothing.

**Why 242 days have no weather category: the feed changed how often it records**

| Riding hours with a reading (of 16) | Days |
|---|---|
| 0 to 4 | 177 |
| 5 to 11 | 65 |
| 12 to 16 | 479 |

237 of the 242 days fall between July 2016 and April 2017. From October 2016 to February 2017 every single day is thin, with readings in only 2.5 to 3.7 of the 16 riding hours on average. From May 2017 the feed covers about 15 of 16 hours on almost every day. So this is not a few outages: the feed recorded only every few hours in its first months, then switched to about hourly. The weather comparisons therefore rest mostly on March 2017 to June 2018, which still covers every season, including the winter of 2017 to 2018.

## Power BI connection (8 Oct 2026, `03_powerbi_access.sql`)

- REPORTER now reads MARTS and nothing else. Checked as REPORTER with secondary roles switched off: the daily mart returns its 725 rows, and the same query on STAGING is refused.
- Power BI signs in as POWERBI_USER with a key pair and loads the three marts in Import mode: 725 rows in dim_date, 725 in fct_daily_trips_weather and 17,400 in fct_hourly_trips_weather (725 days of 24 hours), the same as in Snowflake.
- When a key-pair sign-in fails, Power BI only says it could not authenticate. Snowflake's login history gives the reason. Here it was JWT_TOKEN_INVALID_PUBLIC_KEY_FINGERPRINT_MISMATCH: the public key registered for the user did not belong to the private key Power BI sent. Registering the public key derived from the private key file, and comparing the two fingerprints before connecting, fixed it. Both checks are now part of `03_powerbi_access.sql`.

## Assumptions

1. **Trip timestamps are New York local time.** The files carry no time zone. **Confirmed after loading (check 5e):** trip starts peak at 08:00 and 17:00 and are lowest at 04:00, which is the commuter pattern in local time. If the times were UTC, the peaks would fall at 12:00 to 13:00 and 21:00 to 22:00.
2. **Weather timestamps are UTC.** Unix time is UTC by definition.
3. **One weather point represents the whole city.** All trips are matched to the New York City weather location, even though conditions can differ a little between boroughs.
4. **Weather units follow OpenWeatherMap's standard set.** The files do not say; Kelvin temperatures point to it.
5. **Days with no trips were system closures for snow.** The data has no closure field, but all 8 such days start on the day of a major snowstorm. Our own readings show snow on every day of the March 2017 closure. On 9 Feb 2017 the feed has only 3 readings, too few to show the blizzard, but the National Weather Service recorded 24 cm of snow in Central Park that day.

## Decisions

| # | Decision | Why |
|---|---|---|
| 1 | Use weather location 5128581 (New York City) only | Its coordinates are in Lower Manhattan. The other "New York" is about 280 km away and would overstate snow about six times. |
| 2 | Analysis window: 6 July 2016 to 30 June 2018 (725 days) | It is the only period both sources cover in full. The weather starts at 22:31 UTC on 5 July 2016, which is 18:31 in New York, so 5 July has evening weather only and is left out. Trips end on 30 June 2018. All trips stay loaded; trips outside the window have no weather to match. |
| 3 | Convert weather time from UTC to New York local time before joining | Trips are in local time. Without converting, every match would be 4 to 5 hours out. |
| 4 | Convert temperature from Kelvin to Celsius | Kelvin is not meaningful to a business audience. |
| 5 | Combine weather readings to one row per hour (and per day) before joining to trips | Some hours have several readings, which would otherwise duplicate trips in the join. |
| 6 | Keep birth year and gender out of every dbt model; they stay only in RAW | They are not needed to answer the weather question, so leaving them out reduces personal data from the first model onwards. User type stays, because it is central to the analysis. |
| 7 | Flag problem records rather than delete them | For example, trips with no end station stay in the data with a flag, so I can always explain what was excluded and why. |
| 8 | Check every condition in a reading, not just the first, when flagging rain or snow | 21% of readings list more than one condition. Looking only at the first would undercount rain and snow. |
| 9 | Convert every weather measure to an explicit number type in staging | The same field is sometimes a decimal and sometimes a whole number. |
| 10 | Decide "rainy" and "snowy" from the condition labels, not from rain or snow amounts | Amounts are missing for about two thirds of rain-labelled readings, so they cannot tell wet from dry. Amounts can still show intensity where present. |
| 11 | Keep one reading per time in staging. A dbt test checks that readings sharing a time are exact copies | 27% of readings repeat a time already seen, which would double-count weather. If the repeats are exact copies, it does not matter which one is kept; the test warns if they are not. |
| 12 | Use daily weather as the main grain, with hourly as a second view | Some hours probably have no reading, so daily figures are more complete. Hourly views must allow for gaps. |
| 13 | Load RAW as received: trip values as text and each weather record as its original JSON, plus the source file, line number and load time | A value that does not fit a type cannot break the load or silently become blank. Every conversion happens in dbt, where it is visible and tested, and any row can be traced back to its file. |
| 14 | Read empty fields and the text NULL in the trip files as missing values | That is how the files mark a missing value, so missing values always look the same in RAW. Hashmap's published version of the lab SQL does the same. |
| 15 | Keep membership type in staging but leave it out of the analysis | It exists for 2018 trips only, so it covers just a quarter of the analysis window. |
| 16 | Keep trips with no user type, labelled "Unknown" | They are real trips (51,780 in 2016 and 2017), so they count in every total and show as Unknown in any split by user type. This follows decision 7: flag, do not delete. |
| 17 | Compare weather effects within the same month and type of day (weekday or weekend), not across the whole window | Usage grew 18% from 2016 to 2017 and swings strongly with the seasons. Comparing all rainy days with all dry days would mix growth and season into the weather effect. |
| 18 | Build the daily model on a full calendar, so the 4 closure days in the window appear with zero trips and a closure flag. Leave closed days out when measuring how riders respond to weather, and report the closures as a separate finding | A model built only from trip records would silently drop days with no trips, and with them the biggest weather effect in the data: snow that shut the system. But riders had no choice on those days, so counting them as rider behaviour would exaggerate the effect of snow. That leaves 721 open days in the window. |
| 19 | dbt connects to Snowflake as the service user DBT_CLOUD_USER with a key pair, for both development and the scheduled job, which write to different schemas | A service user cannot sign in with a password, and the private key lives only in dbt and on my laptop, never in the repository. With one developer, a second Snowflake user for development would add setup without adding safety; in a team, each developer would use their own user. |
| 20 | Run dbt on the v1 Latest release track instead of the default, v2 Stable | On the free Developer plan, v2 shows documentation only in Catalog, which that plan does not include. v1 Latest keeps dbt Docs, which I need to show the lineage and column descriptions. The YAML follows the newer conventions, so moving to v2 later is easy. |
| 21 | Count every published trip, including very short trips that start and end at the same station | Citibike already removes staff trips, test-station trips and trips under 60 seconds before publishing. What remains are real rentals. |
| 22 | Keep station and bike IDs as text | They are labels, not quantities. Text keeps any ID that is not a number intact. |
| 23 | Build development models in DBT_DEV and production models in STAGING, INTERMEDIATE, MARTS and REFERENCE | Work in progress never touches what Power BI reads. This uses generate_schema_name_for_env, which ships with dbt. |
| 24 | Build the trip staging model as a table and the other staging models as views | 61 million rows of text are converted once, instead of again in every test and every model downstream. The weather model is small enough to stay a view. |
| 25 | Count a reading as rain when any label is Rain, Drizzle or Thunderstorm, and as snow when any label is Snow | Drizzle is light rain, and thunderstorms in New York bring rain. Mist, Haze and Fog reduce visibility but are not rain. |
| 26 | Judge a day's weather on its riding hours, 06:00 to 21:59 | These 16 hours hold 93% of all trips. Rain at 03:00 does not stop anyone riding. |
| 27 | Use a day in weather comparisons only if at least 12 of its 16 riding hours have a weather reading. Otherwise label it "Not enough weather data" | The feed is thin on some days, worst of all during storms (3 readings on 9 Feb 2017). Guessing the weather of those days would be less honest than setting them aside and saying how many there are. Checked after the build: 242 days fall below the line, almost all from July 2016 to April 2017, when the feed recorded only every few hours. Counting rain hours from 3 readings a day would undercount rain, so the rule stays. 479 days still qualify, covering every season. |
| 28 | Compare each day with a typical dry day: the median trips of dry, open days in the same month and year with the same day type | This takes season, growth (18% a year) and the weekday pattern out of the comparison, as decision 17 requires. The median ignores the odd unusual day. |
| 29 | Count US federal holidays as weekends | Commuting drops on holidays just as it does on a Saturday. 22 holidays fall in the window; the list comes from the python-holidays package, which follows the official US rules, and is stored as a dbt seed. |
| 30 | Weather categories for a day: Snow if any riding hour had snow; Rain if 3 or more did; Light rain if 1 or 2 did; otherwise Dry | A single wet hour should not make a whole day count as rainy. The categories are easy to explain, and the rain hours stay in the data as a number for finer charts. |
| 31 | Shape the marts as a star schema: a date dimension plus a daily and an hourly fact table | One date table filters both fact tables in Power BI, which is the standard pattern for date-based reports. |
| 32 | Set the analysis window, the riding hours and the coverage threshold once, as dbt variables | Every model uses the same values, and changing one setting changes it everywhere. |
| 33 | Limit REPORTER to the MARTS schema | Power BI needs only the marts. Staging holds 61 million trip-level rows and intermediate tables are building blocks that may change, so keeping the report role out of them follows least privilege and keeps reports on the tested, documented layer. |
| 34 | Power BI connects as its own service user, POWERBI_USER, with a key pair and only the REPORTER role | There is no password to leak or expire, and it is separate from dbt's user, so either can be cut off without affecting the other. |
| 35 | Load the marts into Power BI in Import mode, not DirectQuery | About 19,000 rows of historical data that does not change. Imported data makes every visual fast, uses no warehouse credits per click, and the report keeps working without a live connection. |
| 36 | Give each computer that runs Power BI its own key, and check the fingerprint before connecting | Each key can be removed on its own: a second computer uses the user's second key slot (RSA_PUBLIC_KEY_2), which is unset when it is no longer needed. Comparing the fingerprint in Snowflake with the key file catches a mismatched key before Power BI tries to sign in. |

## Open questions

- Was service only partly running on the days just before or after each closure? (Check the daily trip counts around each closure.)
- Are 1 to 2 and 3 or more rainy riding hours the right split between Light rain and Rain? Light rain shows no effect at all, so the split looks sensible; a chart of trips against rain hours in Power BI will show it directly.
