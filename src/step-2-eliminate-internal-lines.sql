begin;
drop table if exists internal_lines;
create table internal_lines (
       line_id text,
       station_id text
);
insert into internal_lines (line_id, station_id)
       select l.osm_id as line_id, s.osm_id as station_id
              from power_line l join power_station s
                   on ST_Contains(s.area, l.extent);
delete from power_line where osm_id in (select line_id from internal_lines);
commit;
