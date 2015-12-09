/* simplest, dumbest possible geometric match of lines and statios.. no buffering is applied here! */
select s.osm_id as station_id, l.osm_id as line_id, s.power_name as station_name, l.power_name as line_name,
	ST_AsText(s.location) as location_text, ST_AsText(l.extent) as line_text from power_station s
	join power_line l on ST_Intersects(s.location, l.extent)
	order by s.osm_id desc
	limit 209;
