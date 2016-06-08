begin;
-- TODO this needs a /major/ rework
drop function if exists line_structure_from_source(text);
drop function if exists line_structure_from_lateral_merge(jsonb);
drop function if exists line_structure_from_end_join(jsonb);
drop function if exists line_structure_from_object(jsonb);
drop function if exists line_structure_classify(line_structure array, integer);
drop function if exists line_structure_distance(line_structure, line_structure);
drop function if exists line_structure_majority(line_structure array);
drop table if exists computed_line_structure;
drop type if exists line_structure;

create type line_structure as (
    -- properties
    voltage integer,
    frequency float,
    cables integer,
    wires integer,
    -- counts
    num_objects integer,
    num_conflicts integer array[4],
    num_classes integer
);

create table computed_line_structure (
    line_id integer primary key,
    line_structure line_structure
);


create function line_structure_from_object(o jsonb) returns line_structure array as $$
begin
    return case when o ? 'source' then line_structure_from_source(o->>'source')
                when o ? 'merge'  then line_structure_from_lateral_merge(o)
                when o ? 'join'   then line_structure_from_end_join(o)
                when o ? 'split'  then line_structure_from_object(o->'split'->0) end;
end;
$$ language plpgsql;

create function line_structure_from_lateral_merge(m jsonb) returns line_structure array as $$
begin
    return array(select unnest(line_structure_from_object(o)) from jsonb_array_elements(j->'merge') ar(o));
end;
$$ language plpgsql;

create function line_structure_from_end_join(j jsonb) returns line_structure array as $$
declare
    raw_data line_structure array;
    num_classes integer;
    stripe_class integer[][];
begin
--    raise notice 'electric structure from end join on %', j::text;
    raw_data = array(select unnest(line_structure_from_object(o)) from jsonb_array_elements(j->'join') ar(o));
    num_classes = max((e).num_classes) from unnest(raw_data) as e;
    if num_classes > 1 then
        raise notice 'implement classification!';
    end if;
    return raw_data;
end;
$$ language plpgsql;

create function line_structure_from_source(o text) returns line_structure array as $$
begin
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

create function line_structure_majority(data_array line_structure array) returns line_structure as $$
declare
    r line_structure;
begin
    with raw_data (voltage, frequency, cables, wires, num_objects, num_conflicts, num_classes) as (select (e).* from unnest(data_array) e),
    cnt( c_t, c_v, c_f, c_c, c_w, n_s ) as (
        select sum(num_objects),
               coalesce(sum(num_objects) filter (where voltage is not null), 0),
               coalesce(sum(num_objects) filter (where frequency is not null), 0),
               coalesce(sum(num_objects) filter (where cables is not null), 0),
               coalesce(sum(num_objects) filter (where wires is not null), 0),
               max(num_stripes)
          from raw_data
    ),
    vlt(voltage, conflicts) as (
        select voltage, c_v - score from (
             select voltage, sum(num_objects) - sum(num_conflicts[1])
               from raw_data
           group by voltage
        ) _t (voltage, score), cnt
        order by voltage is not null desc, score desc, voltage asc limit 1
    ),
    frq(frequency, conflicts) as (
        select frequency, c_f - score from (
             select frequency, sum(num_objects) - sum(num_conflicts[1])
               from raw_data
           group by frequency
        ) _t (frequency, score), cnt
        order by frequency is not null desc, score desc, frequency asc limit 1
    ),
    cbl(cables, conflicts) as (
        select cables, c_c - score from (
             select cables, sum(num_objects) - sum(num_conflicts[1])
               from raw_data
           group by cables
        ) _t (cables, score), cnt
        order by cables is not null desc, score desc, cables asc limit 1
    ),
    wrs(wires, conflicts) as (
        select wires, c_w - score from (
             select wires, sum(num_objects) - sum(num_conflicts[1])
               from raw_data
           group by wires
        ) _t (wires, score), cnt
        order by wires is not null desc, score desc, wires asc limit 1
    )
    select vlt.voltage, frq.frequency, cbl.cables, wrs.wires, c_t,
           array[vlt.conflicts, frq.conflicts, cbl.conflicts, wrs.conflicts], n_s
      into r
      from vlt, frq, cbl, wrs, cnt;
    return r;
end;
$$ language plpgsql;


create function line_structure_distance(a line_structure, b line_structure) returns numeric as $$
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



-- temporary table and sequence used for classification algorithm
drop table if exists line_structure_classes;
create table line_structure_classes (
    run_key integer,
    structure_key integer,
    class_key integer,
    primary key (run_key, structure_key)
);

create index line_structure_class_key_idx
          on line_structure_classes (run_key, class_key);
drop sequence if exists line_structure_classify_run_key;
create sequence line_structure_classify_run_key;


create function line_structure_classify (raw_data line_structure array, num_classes integer) returns integer[][] as $$
declare
    my_run_key integer;
    edge record;
    src_key integer;
    dst_key integer;
    num_edges integer;
begin
    num_edges  = 0;
    my_run_key = nextval('line_structure_classify_run_key');
    insert into line_structure_classes (run_key, structure_key, class_key)
         select my_run_key, i, i
           from generate_subscripts(raw_data) _t(i);
    for edge in with pairs (src, dst, cost) as (
        select distinct least(i, j), greatest(i,j),
               line_structure_distance(raw_data[i], raw_data[j])
          from generate_subscripts(raw_data) _t(i),
               generate_subscripts(raw_data) _s(j)
         where i != j
      order by line_structure_distance(raw_data[i], raw_data[j]) asc
    ) select * from pair_cost loop
        src_key := class_key from line_structure_classes c
                            where run_key = my_run_key
                              and structure_key = edge.src;
        dst_key := class_key from line_structure_classes c
                            where run_key = my_run_key
                              and structure_key = edge.dst;
        if src_key = dst_key then
            continue;
        elsif num_edges + num_classes = array_length(raw_data, 1) then
            exit;
        else
            update line_structure_classes
               set class_key = least(src_key, dst_key)
             where run_key = my_run_key
               and class_key = greatest(src_key, dst_key);
        end if;
    end loop;
    return array(select array_agg(structure_key)
                   from line_structure_classes c
                  where run_key = my_run_key
               group by class_key);
end;
$$ language plpgsql;


commit;
