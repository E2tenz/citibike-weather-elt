{{ config(materialized='table') }}

{#
    One row per Citibike trip, with every value converted to its type.

    Built as a table, unlike the rest of staging: its 61 million rows of
    text are converted once here, instead of again in every test and every
    model that reads trips.

    Birth year and gender are left out on purpose (decision 6).
    Station and bike IDs stay text: they are labels, not numbers.
#}

with source as (

    select * from {{ source('raw', 'trips') }}

),

renamed as (

    select
        -- Key and lineage: the file and line each trip came from
        {{ dbt_utils.generate_surrogate_key(['_source_file', '_source_row']) }} as trip_id,
        _source_file,
        _source_row,
        _loaded_at,

        -- New York local time; the files carry no time zone (assumption 1)
        try_to_timestamp_ntz(start_time) as started_at,
        try_to_timestamp_ntz(stop_time) as ended_at,
        try_to_number(trip_duration_sec) as trip_duration_sec,

        start_station_id,
        start_station_name,
        try_to_double(start_station_latitude) as start_station_latitude,
        try_to_double(start_station_longitude) as start_station_longitude,

        end_station_id,
        end_station_name,
        try_to_double(end_station_latitude) as end_station_latitude,
        try_to_double(end_station_longitude) as end_station_longitude,

        bike_id,

        -- Filled for 2018 trips only, so not used in the analysis (decision 15)
        membership_type,

        -- 51,780 trips in 2016 and 2017 have no user type (decision 16)
        coalesce(user_type, 'Unknown') as user_type

    from source

)

select
    *,
    started_at::date as trip_date,
    date_trunc('hour', started_at) as trip_hour,
    end_station_id is not null as has_end_station,
    trip_duration_sec > 86400 as is_over_24_hours

from renamed
