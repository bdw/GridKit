begin;
drop function if exists jsonb_first_key(v jsonb);
drop function if exists electric_structure_from_tags(text);
drop table if exists computed_structure;
drop type if exists electric_structure;

create type electric_structure as (
    -- properties
    voltage integer,
    frequency float,
    cables integer,
    wires integer,
    -- counts
    num_objects integer,
    num_conflicts integer
);

create table computed_structure (
    power_id integer not null,
    power_type char(1),
    power_structure electric_structure,
    primary key(power_id, power_type)
);


create function jsonb_first_key(v jsonb) returns text as $$
begin
     return k from (select jsonb_object_keys(v)) t(k) limit 1;
end;
$$ language plpgsql;



create function electric_structure_from_tags(o text) returns electric_structure array
as $$
declare
    t electric_tags;
    e electric_structure array;
    n integer;
begin
     select * into t from electric_tags where osm_name = o;
     return null;
end;
$$ language plpgsql;

commit;
