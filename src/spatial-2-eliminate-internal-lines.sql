begin;
drop table if exists internal_lines;
create table internal_lines (
    line_id integer primary key,
    station_id integer,
    extent geometry(linestring, 3857)
);
-- todo, merge internal lines information into power station
insert into internal_lines (line_id, station_id, extent)
    select l.line_id, s.station_id, l.extent
       from power_line l join power_station s
           on ST_Contains(s.area, l.extent);

delete from power_line l where exists (
    select 1 from internal_lines i where i.line_id = l.line_id
);
commit;
