{#
    One row per New York City weather reading, typed and converted.

    - Only city ID 5128581, New York City (decision 1).
    - Time converted from UTC to New York local time (decision 3).
    - Temperature converted from Kelvin to Celsius (decision 4).
    - Rain and snow decided from every condition label in a reading, not
      just the first (decisions 8 and 10).
    - Readings that repeat a time are reduced to one (decision 11). The
      test assert_weather_repeats_are_identical checks that repeats are
      exact copies, so it does not matter which copy is kept.
#}

with source as (

    select * from {{ source('raw', 'weather') }}

),

new_york_city as (

    select
        raw_json,
        _source_file,
        _source_row
    from source
    where raw_json:city.id::int = 5128581

),

conditions as (

    -- Every condition label in a reading, for example Rain and Mist
    select
        r._source_file,
        r._source_row,
        array_agg(distinct c.value:main::string)
            within group (order by c.value:main::string) as condition_labels
    from new_york_city as r,
        lateral flatten(input => r.raw_json:weather) as c
    group by r._source_file, r._source_row

),

typed as (

    select
        to_timestamp_ntz(r.raw_json:time::int) as observed_at_utc,
        convert_timezone(
            'UTC', 'America/New_York', to_timestamp_ntz(r.raw_json:time::int)
        ) as observed_at_local,

        round(r.raw_json:main.temp::float - 273.15, 2) as temp_c,
        round(r.raw_json:main.temp_min::float - 273.15, 2) as temp_min_c,
        round(r.raw_json:main.temp_max::float - 273.15, 2) as temp_max_c,
        r.raw_json:main.humidity::float as humidity_pct,
        r.raw_json:main.pressure::float as pressure_hpa,
        r.raw_json:clouds.all::float as cloud_cover_pct,
        r.raw_json:wind.speed::float as wind_speed_ms,
        r.raw_json:wind.gust::float as wind_gust_ms,

        -- Amounts are missing from most readings, even rainy ones (finding 20)
        r.raw_json:rain."1h"::float as rain_1h_mm,
        r.raw_json:rain."3h"::float as rain_3h_mm,
        r.raw_json:snow."1h"::float as snow_1h_mm,

        r.raw_json:weather[0].main::string as main_condition,
        r.raw_json:weather[0].description::string as main_condition_detail,
        c.condition_labels,
        arrays_overlap(
            c.condition_labels, array_construct('Rain', 'Drizzle', 'Thunderstorm')
        ) as is_rain,
        array_contains('Snow'::variant, c.condition_labels) as is_snow,

        r._source_file,
        r._source_row

    from new_york_city as r
    left join conditions as c
        on
            r._source_file = c._source_file
            and r._source_row = c._source_row

)

select * from typed
qualify row_number() over (
    partition by observed_at_utc
    order by _source_file, _source_row
) = 1
