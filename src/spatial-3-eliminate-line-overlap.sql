begin;
drop table if exists line_intersections;
drop table if exists split_lines;
drop table if exists cropped_lines;

create table line_intersections (
    line_id    integer primary key,
    station_id integer array,
    extent geometry(linestring, 3857),
    areas  geometry(multipolygon, 3857)
);

create table split_lines (
    new_id integer,
    old_id integer,
    segment geometry(linestring, 3857)
);

create table cropped_lines (
    line_id integer primary key,
    old_extent geometry(linestring, 3857),
    new_extent geometry(linestring, 3857)
);

insert into line_intersections (line_id, station_id, extent, areas)
    select l.line_id, array_agg(s.station_id), l.extent, st_multi(st_union(s.area))
        from power_line l
        join power_station s on st_intersects(l.extent, s.area)
        group by l.line_id, l.extent;

insert into split_lines (new_id, old_id, segment)
    select nextval('line_id'), line_id, (st_dump(st_difference(extent, areas))).geom
        from line_intersections
        where st_numgeometries(st_difference(extent,areas)) > 1;

insert into cropped_lines(line_id, old_extent, new_extent)
     select line_id, extent, st_difference(extent, areas)
         from line_intersections
         where st_numgeometries(st_difference(extent, areas)) = 1;

insert into power_line (line_id, power_name, extent, terminals)
    select s.new_id, l.power_name, s.segment,
           minimal_terminals(s.segment, i.areas, l.terminals)
        from split_lines s
        join line_intersections i on i.line_id = s.old_id
        join power_line l on l.line_id = s.old_id;

insert into osm_objects (power_id, power_type, objects)
    select new_id, 'l', track_objects(array[old_id], 'l', 'split') from split_lines;

update power_line l set extent = c.new_extent
     from cropped_lines c where c.line_id = l.line_id;

delete from power_line where line_id in (
    select old_id from split_lines
);

commit;
