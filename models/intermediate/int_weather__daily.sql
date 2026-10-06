{#
    New York City weather per local day, built from the hourly model.

    Coverage is measured, not assumed: some days have far fewer readings
    than others (on 9 Feb 2017, a blizzard day, there are only 3). The
    daily mart uses daytime_hours_with_weather to decide whether a day has
    enough data for weather comparisons (decision 27).

    Daytime means the riding hours set in dbt_project.yml, 06:00 to 21:59,
    which hold 93% of all trips (decision 26).
#}

{% set daytime -%}
    hour(weather_hour) between {{ var('daytime_first_hour') }} and {{ var('daytime_last_hour') }}
{%- endset %}

select
    weather_hour::date as weather_date,
    count(*) as hours_with_weather,
    count_if({{ daytime }}) as daytime_hours_with_weather,
    avg(avg_temp_c) as avg_temp_c,
    min(min_temp_c) as min_temp_c,
    max(max_temp_c) as max_temp_c,
    avg(avg_humidity_pct) as avg_humidity_pct,
    avg(avg_wind_speed_ms) as avg_wind_speed_ms,
    max(max_wind_gust_ms) as max_wind_gust_ms,
    count_if(is_rain) as rain_hours,
    count_if(is_snow) as snow_hours,
    count_if(is_rain and {{ daytime }}) as daytime_rain_hours,
    count_if(is_snow and {{ daytime }}) as daytime_snow_hours

from {{ ref('int_weather__hourly') }}
group by weather_date
