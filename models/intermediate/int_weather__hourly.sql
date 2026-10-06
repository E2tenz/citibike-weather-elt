{#
    New York City weather per local hour: one row per hour with at least
    one reading. Hours without a reading are absent; the hourly mart shows
    them as "No reading" rather than guessing.

    An hour counts as rainy or snowy if any reading in it is (decisions 8,
    10 and 25). Rain amounts are kept only as the largest reported value,
    because most readings carry no amount at all.
#}

select
    date_trunc('hour', observed_at_local) as weather_hour,
    count(*) as readings,
    avg(temp_c) as avg_temp_c,
    min(temp_c) as min_temp_c,
    max(temp_c) as max_temp_c,
    avg(humidity_pct) as avg_humidity_pct,
    avg(cloud_cover_pct) as avg_cloud_cover_pct,
    avg(wind_speed_ms) as avg_wind_speed_ms,
    max(wind_gust_ms) as max_wind_gust_ms,
    max(rain_1h_mm) as max_rain_1h_mm,
    boolor_agg(is_rain) as is_rain,
    boolor_agg(is_snow) as is_snow

from {{ ref('stg_weather__readings') }}
group by weather_hour
