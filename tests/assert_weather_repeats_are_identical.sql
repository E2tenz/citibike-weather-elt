{{ config(severity='warn') }}

{#
    Decision 11 keeps one reading per time. That is only safe if readings
    that share a time are exact copies. This test lists every New York City
    time whose repeats differ in any way. It warns instead of failing, so
    the number can be reported and looked into.
#}

select
    raw_json:time::int as observed_epoch,
    count(*) as readings,
    count(distinct raw_json::string) as distinct_versions
from {{ source('raw', 'weather') }}
where raw_json:city.id::int = 5128581
group by observed_epoch
having count(distinct raw_json::string) > 1
