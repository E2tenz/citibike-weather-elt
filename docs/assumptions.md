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

## Assumptions

1. **Trip timestamps are New York local time.** The files carry no time zone. **Confirmed after loading (check 5e):** trip starts peak at 08:00 and 17:00 and are lowest at 04:00, which is the commuter pattern in local time. If the times were UTC, the peaks would fall at 12:00 to 13:00 and 21:00 to 22:00.
2. **Weather timestamps are UTC.** Unix time is UTC by definition.
3. **One weather point represents the whole city.** All trips are matched to the New York City weather location, even though conditions can differ a little between boroughs.
4. **Weather units follow OpenWeatherMap's standard set.** The files do not say; Kelvin temperatures point to it.
5. **Days with no trips were system closures for snow.** The data has no closure field, but all 8 such days start on the day of a major snowstorm. I will check this against the project's own weather readings for the two 2017 closures, which fall inside the weather data.

## Decisions

| # | Decision | Why |
|---|---|---|
| 1 | Use weather location 5128581 (New York City) only | Its coordinates are in Lower Manhattan. The other "New York" is about 280 km away and would overstate snow about six times. |
| 2 | Analysis window: 6 July 2016 to 30 June 2018 (725 days) | It is the only period both sources cover in full. The weather starts at 22:31 UTC on 5 July 2016, which is 18:31 in New York, so 5 July has evening weather only and is left out. Trips end on 30 June 2018. All trips stay loaded; trips outside the window have no weather to match. |
| 3 | Convert weather time from UTC to New York local time before joining | Trips are in local time. Without converting, every match would be 4 to 5 hours out. |
| 4 | Convert temperature from Kelvin to Celsius | Kelvin is not meaningful to a business audience. |
| 5 | Combine weather readings to one row per hour (and per day) before joining to trips | Some hours have several readings, which would otherwise duplicate trips in the join. |
| 6 | Keep birth year and gender out of the reporting models | They are not needed to answer the weather question, so leaving them out reduces personal data in the reports. User type stays, because it is central to the analysis. |
| 7 | Flag problem records rather than delete them | For example, trips with no end station stay in the data with a flag, so I can always explain what was excluded and why. |
| 8 | Check every condition in a reading, not just the first, when flagging rain or snow | 21% of readings list more than one condition. Looking only at the first would undercount rain and snow. |
| 9 | Convert every weather measure to an explicit number type in staging | The same field is sometimes a decimal and sometimes a whole number. |
| 10 | Decide "rainy" and "snowy" from the condition labels, not from rain or snow amounts | Amounts are missing for about two thirds of rain-labelled readings, so they cannot tell wet from dry. Amounts can still show intensity where present. |
| 11 | Remove duplicate readings in staging, keeping one per timestamp | 27% of readings repeat a time already seen, which would double-count weather. |
| 12 | Use daily weather as the main grain, with hourly as a second view | Some hours probably have no reading, so daily figures are more complete. Hourly views must allow for gaps. |
| 13 | Load RAW as received: trip values as text and each weather record as its original JSON, plus the source file, line number and load time | A value that does not fit a type cannot break the load or silently become blank. Every conversion happens in dbt, where it is visible and tested, and any row can be traced back to its file. |
| 14 | Read empty fields and the text NULL in the trip files as missing values | That is how the files mark a missing value, so missing values always look the same in RAW. Hashmap's published version of the lab SQL does the same. |
| 15 | Keep membership type in staging but leave it out of the analysis | It exists for 2018 trips only, so it covers just a quarter of the analysis window. |
| 16 | Keep trips with no user type, labelled "Unknown" | They are real trips (51,780 in 2016 and 2017), so they count in every total and show as Unknown in any split by user type. This follows decision 7: flag, do not delete. |
| 17 | Compare weather effects within the same month and type of day (weekday or weekend), not across the whole window | Usage grew 18% from 2016 to 2017 and swings strongly with the seasons. Comparing all rainy days with all dry days would mix growth and season into the weather effect. |
| 18 | Build the daily model on a full calendar, so the 4 closure days in the window appear with zero trips and a closure flag. Leave closed days out when measuring how riders respond to weather, and report the closures as a separate finding | A model built only from trip records would silently drop days with no trips, and with them the biggest weather effect in the data: snow that shut the system. But riders had no choice on those days, so counting them as rider behaviour would exaggerate the effect of snow. That leaves 721 open days in the window. |
| 19 | dbt connects to Snowflake as the service user DBT_CLOUD_USER with a key pair, for both development and the scheduled job, which write to different schemas | A service user cannot sign in with a password, and the private key lives only in dbt and on my laptop, never in the repository. With one developer, a second Snowflake user for development would add setup without adding safety; in a team, each developer would use their own user. |
| 20 | Run dbt on the v1 Latest release track instead of the default, v2 Stable | On the free Developer plan, v2 shows documentation only in Catalog, which that plan does not include. v1 Latest keeps dbt Docs, which I need to show the lineage and column descriptions. The YAML follows the newer conventions, so moving to v2 later is easy. |

## Open questions

- Do the project's own weather readings show snow or ice on 9 Feb and 14 to 16 Mar 2017? (Check in staging.)
- Was service only partly running on the days just before or after each closure? (Check the daily trip counts around each closure.)
- Are readings with the same time identical copies, or different readings? (Decides how to remove duplicates.)
- Is 102 mm of snow in one hour real, or an error?
- Should very short same-station trips count as real trips?
