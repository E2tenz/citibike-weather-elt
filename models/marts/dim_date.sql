{#
    Calendar for the analysis window, one row per day (decision 2).
    Power BI uses it as the date table for both fact tables.

    US federal holidays count as weekends in day_type (decision 29):
    commuting drops on them just as it does on a Saturday.
#}

with days as (

    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('" ~ var('analysis_start_date') ~ "' as date)",
        end_date="dateadd(day, 1, cast('" ~ var('analysis_end_date') ~ "' as date))"
    ) }}

),

holidays as (

    select
        holiday_date,
        holiday_name
    from {{ ref('us_federal_holidays') }}

)

select
    days.date_day,
    year(days.date_day) as calendar_year,
    month(days.date_day) as month_number,
    monthname(days.date_day) as month_name,
    to_char(days.date_day, 'YYYY-MM') as year_month,
    dayofweekiso(days.date_day) as day_of_week_number,
    dayname(days.date_day) as day_name,
    dayofweekiso(days.date_day) in (6, 7) as is_weekend,
    holidays.holiday_date is not null as is_holiday,
    holidays.holiday_name,
    case
        when dayofweekiso(days.date_day) in (6, 7) or holidays.holiday_date is not null
            then 'Weekend or holiday'
        else 'Weekday'
    end as day_type,
    case
        when month(days.date_day) in (12, 1, 2) then 'Winter'
        when month(days.date_day) in (3, 4, 5) then 'Spring'
        when month(days.date_day) in (6, 7, 8) then 'Summer'
        else 'Autumn'
    end as season

from days
left join holidays
    on days.date_day = holidays.holiday_date
