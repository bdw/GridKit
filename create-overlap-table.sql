begin;
drop table if exists station_line;
create table station_line (
	line_id varchar(64),
	station_id varchar(64),
	overlap geometry(geometry, 3857),
	primary key (line_id, station_id)
);
insert into station_line (line_id, station_id, overlap)
	select l.osm_id as line_id, s.osm_id as station_id, st_intersection(s.area, l.terminals) as overlap
		from power_line l join power_station s on ST_Intersects(s.area, l.terminals);
create index station_line_overlap on station_line using gist(overlap);
commit;
