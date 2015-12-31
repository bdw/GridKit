
with way_stations as (
	select concat('w', id) as osm_id, hstore(tags) as tags, 
		case when st_isclosed(line) then st_makepolygon(line)
		     when st_npoints(line) = 2 then st_buffer(line, 1)
		     else st_makepolygon(st_addpoint(line, st_startpoint(line))) end as geom
		from planet_osm_ways w
		join way_geometry g on g.way_id = w.id
		where hstore(tags)->'power' in (
			select power_name from power_type_names
				where power_type = 's'
		)
)

insert into power_station (osm_id, power_name, tags, location, area, source_objects) 
	select osm_id, tags->'power', tags, st_centroid(geom), st_convexhull(st_buffer(geom, 100)), array[osm_id]
		from way_stations;
