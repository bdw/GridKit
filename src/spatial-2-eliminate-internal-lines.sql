begin;
drop table if exists internal_lines;
create table internal_lines (
    line_id varchar(64),
    station_id varchar(64),
    extent geometry(linestring, 3857)
);
-- todo, merge internal lines information into power station
insert into internal_lines (line_id, station_id, extent)
    select l.osm_id, s.osm_id, l.extent
       from power_line l join power_station s
           on ST_Contains(s.area, l.extent);

delete from power_line where osm_id in (select line_id from internal_lines);
commit;
