select a.osm_id, b.osm_id from power_line a
	join power_line b on ST_Intersects(a.terminals, b.extent)
				and not ST_Intersects(a.terminals, b.terminals);
