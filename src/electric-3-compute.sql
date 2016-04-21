begin;
drop function if exists electric_structure_from_tags(text);
drop function if exists electric_structure_from_lateral_merge(jsonb);
drop function if exists electric_structure_from_end_join(jsonb);
drop function if exists electric_structure_from_object(jsonb);
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



create function electric_structure_from_object(o jsonb) returns electric_structure array as $$
begin
    return case when o ? 'source' then electric_structure_from_tags(o->>'source')
                when o ? 'merge' then electric_structure_from_lateral_merge(o)
                when o ? 'join'  then electric_structure_from_end_join(o)
                when o ? 'split' then electric_structure_from_object(o->'split'->0) end;
end;
$$ language plpgsql;

create function electric_structure_from_lateral_merge(m jsonb) returns electric_structure array as $$
begin
    return null;
end;
$$ language plpgsql;

create function electric_structure_from_end_join(j jsonb) returns electric_structure array as $$
begin
    return null;
end;
$$ language plpgsql;

create function electric_structure_from_tags(o text) returns electric_structure array
as $$
begin
     return array(select row(v, f, c, w, 1, 0) from (
          select case when voltage is not null then unnest(voltage) end,
                 case when frequency is not null then unnest(frequency) end,
                 case when cables is not null then unnest(cables) end,
                 case when wires is not null then unnest(wires) end
                 from electric_tags where osm_name = o
          ) e (v, f, c, w)
     );
end;
$$ language plpgsql;

commit;
