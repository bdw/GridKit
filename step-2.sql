
select l.osm_id as line_id, s.osm_id as station_id from power_line l
	join power_station s on ST_Intersects(l.extent, s.area) and not ST_Intersects(l.terminals, s.area);
