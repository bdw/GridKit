with node_stations as (
	select concat('n', id) as osm_id, hstore(tags) as tags, point
		from planet_osm_nodes n
		join node_geometry g on g.node_id = n.id
		where hstore(tags)->'power' in (
			select power_name from power_type_names where power_type = 's'
		)
)
insert into power_station (osm_id, power_name, tags, location, area, source_objects)
select osm_id, tags->'power', tags,  point, st_buffer(point, 250), array[osm_id] from node_stations;