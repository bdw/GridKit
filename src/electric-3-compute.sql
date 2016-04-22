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
--    raise notice 'electric structure from object %', o::text;
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
declare

begin
    raise notice 'electric structure from end join on %', j::text;
    raw = array(select unnest(electric_structure_from_object(o)) from jsonb_array_elements(j->'join') a(o));
    grp = array(select row((e).voltage, (e).frequency, (e).cables, (e).wires, sum((e).num_objects), sum((e).num_conflicts))
                       from (select unnest(raw)) t(e)
                       group by (e).voltage, (e).frequency, (e).cables, (e).wires);
    return grp;
end;
$$ language plpgsql;

create function electric_structure_from_tags(o text) returns electric_structure array
as $$
begin
     raise notice 'electric structure from tags on %', o;
     return array(select row(v, f, c, w, 1, 0) from (
          select case when voltage is not null then unnest(voltage) end,
                 case when frequency is not null then unnest(frequency) end,
                 case when cables is not null then unnest(cables) end,
                 case when wires is not null then unnest(wires) end
                 from electric_tags where source_id = o
          ) e (v, f, c, w)
     );
end;
$$ language plpgsql;

commit;
