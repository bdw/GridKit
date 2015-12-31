select a.osm_id, b.osm_id from power_line a
	join power_line b on st_intersects(a.terminals, b.terminals)
		and not exists (select * from station_line s where line_id = a.osm_id and st_intersects(s.overlap, b.terminals))
		limit 50;