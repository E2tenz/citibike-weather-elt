{#
    Decides which Snowflake schema each model is built in.

    Production (target name "prod"): the schema set for the folder in
    dbt_project.yml, so models land in STAGING and later MARTS.
    Anywhere else, such as development: every model goes to the
    developer schema (DBT_DEV), so work in progress never touches the
    tables Power BI reads.

    generate_schema_name_for_env is a macro that ships with dbt.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {{ generate_schema_name_for_env(custom_schema_name, node) }}
{%- endmacro %}
