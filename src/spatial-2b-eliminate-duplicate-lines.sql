begin;
drop table if exists duplicate_lines;
create table duplicate_lines (
    a varchar(64),
    b varchar(64),
    e geometry(linestring, 3857),
    o text[]
);

insert into duplicate_lines (a, b, e, o)
    select distinct least(a.osm_id, b.osm_id), greatest(a.osm_id, b.osm_id),
           a.extent, source_line_objects(a.objects || b.objects)
       from power_line a, power_line b
       where a.extent && b.extent -- suggest index use
       and a.osm_id != b.osm_id   -- not the same line obviously
       and a.extent = b.extent;   -- absolutely identical lines;

update power_line l set objects = d.o, tags = null
       from duplicate_lines d where d.a = l.osm_id;

delete from power_line where osm_id in (select b from duplicate_lines);
commit;
