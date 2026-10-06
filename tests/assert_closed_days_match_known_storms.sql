{#
    The only days in the window with no trips should be the two snowstorm
    closures found when loading: 9 Feb 2017 and 14 to 16 Mar 2017.
    Returns any day that is closed but not expected, or expected but open.
#}

with expected as (

    select column1::date as date_day
    from values ('2017-02-09'), ('2017-03-14'), ('2017-03-15'), ('2017-03-16')

),

closed as (

    select date_day
    from {{ ref('fct_daily_trips_weather') }}
    where is_system_closed

)

select
    coalesce(expected.date_day, closed.date_day) as date_day,
    expected.date_day is not null as is_expected,
    closed.date_day is not null as is_closed
from expected
full outer join closed
    on expected.date_day = closed.date_day
where expected.date_day is null or closed.date_day is null
