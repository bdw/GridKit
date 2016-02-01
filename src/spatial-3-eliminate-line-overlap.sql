begin;
drop table if exists line_intersections;
drop table if exists split_lines;

create table line_intersections (
    line_id varchar(64),
    station_id text[],
    extent geometry(linestring, 3857),
    areas  geometry(multipolygon, 3857),
    primary key (line_id)
);

create table split_lines (
    synth_id varchar(64),
    source_id varchar(64),
    segment geometry(linestring, 3857)
);

insert into line_intersections (line_id, station_id, extent, areas)
    select l.osm_id, array_agg(s.osm_id), l.extent, st_multi(st_union(s.area))
        from power_line l
        join power_station s on st_intersects(l.extent, s.area)
        group by l.osm_id, l.extent;

insert into split_lines (synth_id, source_id, segment)
    select concat('s', nextval('synthetic_objects')), line_id,
            (st_dump(st_difference(extent, areas))).geom as segment
        from line_intersections;

insert into power_line (osm_id, power_name, tags, extent, terminals, objects)
    select s.synth_id, l.power_name, l.tags, s.segment,
           minimal_terminals(s.segment, i.areas, l.terminals),
           source_line_objects(array[s.source_id])
        from split_lines s
        join line_intersections i on i.line_id = s.source_id
        join power_line l on l.osm_id = s.source_id;

delete from power_line where osm_id in (select line_id from line_intersections);
commit;
