begin;
-- TODO this needs a /major/ rework
drop function if exists derive_line_structure(integer);
drop function if exists join_line_structure(integer, integer array);
drop function if exists merge_line_structure(integer, integer array);
drop function if exists line_structure_majority(integer, line_structure array);
drop function if exists line_structure_distance(line_structure, line_structure);
drop function if exists line_structure_classify(integer, line_structure array, integer);
drop table if exists line_structure;

create table line_structure (
    line_id integer,
    part_nr integer,
    -- properties
    voltage integer,
    frequency float,
    cables integer,
    wires integer,
    -- counts
    num_objects integer,
    num_conflicts integer array[4],
    num_classes integer,
    primary key (line_id, part_nr)
);

insert into line_structure (line_id, part_nr, voltage, frequency, cables, wires, num_objects, num_conflicts, num_classes)
     select line_id, generate_series(1, num_classes),
            case when voltage is not null then unnest(voltage) end,
            case when frequency is not null then unnest(frequency) end,
            case when cables is not null then unnest(cables) end,
            case when wires is not null then unnest(wires) end,
            1, array[0,0,0,0], num_classes
       from line_tags;

create function derive_line_structure (i integer) returns line_structure array as $$
declare
    r line_structure array;
    d derived_objects;
begin
     r = array(select row(l.*) from line_structure l where line_id = i);
     if array_length(r, 1) is not null then
         return r;
     end if;
     select * into d from derived_objects where derived_id = i and derived_type = 'l';
     if d.derived_id is null then
         raise exception 'No derived object for line_id %', i;
     elsif d.operation = 'join' then
         r = join_line_structure(i, d.source_id);
     elsif d.operation = 'merge' then
         r = merge_line_structure(i, d.source_id);
     elsif d.operation = 'split' then
         r = derive_line_structure(d.source_id[1]);
     end if;
     if array_length(r, 1) is null then
         raise exception 'Could not derive line_structure for %', i;
     end if;
     -- store and return
     insert into line_structure (line_id, part_nr, voltage, frequency, cables, wires, num_objects, num_conflicts, num_classes)
          select i, s,
                 (l).voltage, (l).frequency,
                 (l).cables, (l).wires,
                 (l).num_objects, (l).num_conflicts, (l).num_classes
            from (select unnest(r) l, generate_subscripts(r, 1)) f(l, s);
     return r;
end;
$$ language plpgsql;


create function join_line_structure(i integer, j integer array) returns line_structure array as $$
declare
    r line_structure array;
    n integer;
begin
    r = array(select unnest(derive_line_structure(line_id)) from unnest(j) line_id);
    n = max((e).num_classes) from unnest(r) as e;
    if n > 1 then
       return array(select line_structure_majority(i, array_agg(l))
                      from line_structure_classify(i, r, n) c
                      join unnest(r) l on (l).line_id = c.source_id and (l).part_nr = c.part_nr
                     group by c.class_key);
    else
        return array[line_structure_majority(i, r)];
    end if;
    return raw_data;
end;
$$ language plpgsql;


create function merge_line_structure(i integer, j integer array) returns line_structure array as $$
declare
begin

end;
$$ language plpgsql;

create function line_structure_majority(i integer, d line_structure array) returns line_structure as $$
declare
    r line_structure;
begin
--    raise notice 'computing majority for %', i;
    with raw_data (line_id, part_nr, voltage, frequency, cables, wires, num_objects, num_conflicts, num_classes) as (select (e).* from unnest(d) e),
    cnt( c_t, c_v, c_f, c_c, c_w, n_s ) as (
        select sum(num_objects),
               coalesce(sum(num_objects) filter (where voltage is not null), 0),
               coalesce(sum(num_objects) filter (where frequency is not null), 0),
               coalesce(sum(num_objects) filter (where cables is not null), 0),
               coalesce(sum(num_objects) filter (where wires is not null), 0),
               max(num_classes)
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
    select null, null, vlt.voltage, frq.frequency, cbl.cables, wrs.wires, c_t,
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
                when least(a.voltage, b.voltage) = 0 then 4
                else 2*greatest(a.voltage, b.voltage)::float / least(a.voltage, b.voltage)::float end
                +
           case when a.frequency is null or b.frequency is null then 1
                when a.frequency = b.frequency then 0
                when least(a.frequency, b.frequency) = 0 then 4
                else 2*greatest(a.frequency, b.frequency) / least(a.frequency, b.frequency) end
                +
           case when a.cables is null or b.cables is null then 1
                when a.cables = b.cables then 0
                when least(a.cables, b.cables) = 0 then 2
                else 0.7*greatest(a.cables, b.cables)::float / least(a.cables, b.cables)::float end
                +
           case when a.wires is null or b.wires is null then 1
                when a.wires = b.wires then 0
                when least(a.wires, b.wires) = 0 then 2
                else 0.7*greatest(a.wires, b.wires)::float / least(a.wires, b.wires)::float end;
end;
$$ language plpgsql;



-- TODO this needs a structure_id of sorts...
drop table if exists line_structure_class;
create table line_structure_class (
    line_id integer,
    source_id integer,
    part_nr   integer,
    class_key integer,
    primary key (line_id, source_id, part_nr)
);

create index line_structure_class_key_idx
          on line_structure_class (line_id, class_key);

create function line_structure_classify (i integer, r line_structure array, n integer) returns setof line_structure_class as $$
declare
    edge record;
    src_key integer;
    dst_key integer;
    num_edges integer;
begin
    num_edges  = 0;
    insert into line_structure_class (line_id, source_id, part_nr, class_key)
         select i, (unnest(r)).line_id, (unnest(r)).part_nr, generate_subscripts(r, 1);

    for edge in with pairs (src_id, src_pt, dst_id, dst_pt, cost) as (
        select a_id, a_pt, b_id, b_pt, line_structure_distance(_s, _t)
          from unnest(r) _s(a_id, a_pt),
               unnest(r) _t(b_id, b_pt) -- line id is the first column
         where a_id < b_id
      order by line_structure_distance(_s, _t) asc
    ) select * from pairs loop
        src_key := class_key from line_structure_class
                            where line_id = i
                              and source_id = edge.src_id
                              and part_nr = edge.src_pt;
        dst_key := class_key from line_structure_class
                            where line_id = i
                              and source_id = edge.dst_id
                              and part_nr = edge.dst_pt;
        if src_key = dst_key then
            continue;
        elsif num_edges + n = array_length(r, 1) then
            exit;
        else
            update line_structure_class
               set class_key = least(src_key, dst_key)
             where line_id = i
               and class_key = greatest(src_key, dst_key);
            num_edges = num_edges + 1;
        end if;
    end loop;
    return query select line_id, source_id, part_nr, class_key
                   from line_structure_class
                  where line_id = i;
end;
$$ language plpgsql;

commit;
