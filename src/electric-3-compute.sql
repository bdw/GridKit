begin;
drop function if exists electric_structure_from_tags(text);
drop function if exists electric_structure_from_lateral_merge(jsonb);
drop function if exists electric_structure_from_end_join(jsonb);
drop function if exists electric_structure_from_object(jsonb);
drop function if exists electric_structure_classify(electric_structure array, integer);
drop function if exists electric_structure_distance(electric_structure, electric_structure);
drop function if exists electric_structure_majority(electric_structure array);
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
    num_conflicts integer array[4],
    num_stripes integer
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
    raw electric_structure array;
    num_stripes integer;
begin
--    raise notice 'electric structure from end join on %', j::text;
    raw = array(select unnest(electric_structure_from_object(o)) from jsonb_array_elements(j->'join') ar(o));
    num_stripes = max((e).num_stripes) from unnest(raw) as e;
    if num_stripes > 1 then
        raise notice 'implement classification!';
    end if;
    return raw;
end;
$$ language plpgsql;

create function electric_structure_from_tags(o text) returns electric_structure array
as $$
begin
--     raise notice 'electric structure from tags on %', o;
     return array(select row(v, f, c, w, 1, array[0,0,0,0], s) from (
          select case when voltage is not null then unnest(voltage) end,
                 case when frequency is not null then unnest(frequency) end,
                 case when cables is not null then unnest(cables) end,
                 case when wires is not null then unnest(wires) end,
                 greatest(array_length(voltage, 1), array_length(frequency, 1), array_length(cables, 1), array_length(wires, 1))
                 from electric_tags where source_id = o
          ) e (v, f, c, w, s)
     );
end;
$$ language plpgsql;

create function electric_structure_majority(source_data electric_structure array) returns electric_structure as $$
declare
    r electric_structure;
begin
    with t(e) as (select unnest(source_data)),
    cnt( c_t, c_v, c_f, c_c, c_w, n_s ) as (
        select sum((e).num_objects),
               coalesce(sum((e).num_objects) filter (where (e).voltage is not null), 0),
               coalesce(sum((e).num_objects) filter (where (e).frequency is not null), 0),
               coalesce(sum((e).num_objects) filter (where (e).cables is not null), 0),
               coalesce(sum((e).num_objects) filter (where (e).wires is not null), 0),
               max((e).num_stripes)
          from t
    ),
    vlt(voltage, conflicts) as (
        select (e).voltage, c_v - sum((e).num_objects) + sum((e).num_conflicts[1]) from t, cnt
            group by (e).voltage, c_v
            order by c_v - sum((e).num_objects) + sum((e).num_conflicts[1]), (e).voltage
            limit 1
    ),
    frq(frequency, conflicts) as (
        select (e).frequency, c_f - sum((e).num_objects) + sum((e).num_conflicts[2]) from t, cnt
            group by (e).frequency, c_f
            order by c_f - sum((e).num_objects) + sum((e).num_conflicts[2]), (e).frequency
            limit 1
    ),
    cbl(cables, conflicts) as (
        select (e).cables, c_c - sum((e).num_objects) + sum((e).num_conflicts[2]) from t, cnt
            group by (e).cables, c_c
            order by c_c - sum((e).num_objects) + sum((e).num_conflicts[2]), (e).cables
            limit 1
    ),
    wrs(wires, conflicts) as (
        select (e).wires, c_w - sum((e).num_objects) + sum((e).num_conflicts[2]) from t, cnt
            group by (e).wires, c_w
            order by c_w - sum((e).num_objects) + sum((e).num_conflicts[2]), (e).wires
            limit 1
    )
    select vlt.voltage, frq.frequency, cbl.cables, wrs.wires, c_t,
           array[vlt.conflicts, frq.conflicts, cbl.conflicts, wrs.conflicts], n_s
           into r
           from vlt, frq, cbl, wrs, cnt;
    return r;
end;
$$ language plpgsql;

create function electric_structure_classify(raw_data electric_structure array, num_classes integer) returns integer[][] as $$
begin
    -- TODO implement minimum-cost-spanning tree; implement cost-function
    return null;
end;
$$ language plpgsql;

create function electric_structure_distance(a electric_structure, b electric_structure) returns numeric as $$
begin
    return case when a.voltage is null or b.voltage is null then 1
                when a.voltage = b.voltage then 0
                when least(a.voltage, b.voltage) = 0 then 2
                else greatest(a.voltage / b.voltage) / least(a.voltage, b.voltage) end
                +
           case when a.frequency is null or b.frequency is null then 1
                when a.frequency = b.frequency then 0
                when least(a.frequency, b.frequency) = 0 then 2
                else greatest(a.frequency, b.frequency) / least(a.frequency, b.frequency) end
                +
           case when a.cables is null or b.cables is null then 1
                when a.cables = b.cables then 0
                when least(a.cables, b.cables) = 0 then 2
                else greatest(a.cables, b.cables) / least(a.cables, b.cables) end
                +
           case when a.wires is null or b.wires is null then 1
                when a.wires = b.wires then 0
                when least(a.wires, b.wires) = 0 then 2
                else greatest(a.wires, b.wires) / least(a.wires, b.wires) end;
end;
$$ language plpgsql;


commit;
