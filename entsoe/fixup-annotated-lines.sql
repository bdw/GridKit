begin;

drop table if exists sep_annotated_lines;
create table sep_annotated_lines (
     new_id integer primary key,
     old_id integer,
    voltage integer,
    circuits integer
);

with annotated_lines as (
     select e.line_id, s.tags->'text_' txt
       from topology_edges e
       join line_structure s on s.line_id = e.line_id
      where s.tags->'text_' LIKE '%+%'
)
insert into sep_annotated_lines (new_id, old_id, voltage, circuits)
     select nextval('line_id'),
            line_id,
            substring(txt from '\d+\+(\d+)')::int,
            coalesce(substring(txt from '\d+\+\d+ \((\d+)x\d+\)')::int, 1)
       from annotated_lines;

insert into derived_objects (derived_id, derived_type, operation, source_id, source_type)
     select new_id, 'l', 'separate', array[old_id], 'l'
from sep_annotated_lines;

insert into topology_edges (line_id, station_id, line_extent, topology_name)
     select new_id, station_id, line_extent, topology_name
       from sep_annotated_lines s
       join topology_edges e on s.old_id = e.line_id;

insert into line_structure (line_id, voltage, circuits, dc_line,
                            underground, under_construction, tags)
     select new_id, l.voltage, l.circuits,
            dc_line, underground, under_construction, tags
       from sep_annotated_lines l
       join line_structure s on s.line_id = l.new_id;

update topology_nodes n
   set line_id = n.line_id || e.line_id
  from sep_annotated_lines l
  join topology_edges e on e.line_id = l.new_id
 where n.station_id = any(e.station_id);

commit;
