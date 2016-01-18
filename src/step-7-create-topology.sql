begin;
drop table if exists problem_lines;
create table problem_lines (
       line_id varchar(64),
       station_id text[],
       line_extent geoemetry(linestring, 3857),
       line_terminals geometry(geometry, 3857),
       station_area geometry(geometry, 3857)
);

insert into problem_lines (line_id, station_id, line_extent, line_terminals, station_area)
     select l.osm_id as line_id, array_agg(s.osm_id) as station_id, l.extent, l.terminals, st_union(s.area)
            group by l.osm_id, l.extent, l.terminals having count(*) > 2;
commit;
