drop table if exists contained_lines;
create table contained_lines (
       line_id text,
       station_id text
);
insert into contained_lines (line_id, station_id)
       select l.osm_id as line_id, s.osm_id as station_id
              from power_line l join power_station s
                   on ST_Contains(s.area, l.extent);
delete from power_line where osm_id in (select line_id from contained_lines);
