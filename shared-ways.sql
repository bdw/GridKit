/*
drop table if exists way_nodes;
create table way_nodes (
	way_id bigint,
	node_id bigint,
	order_nr int
);
insert into way_nodes (way_id, node_id, order_nr)
	select id, unnest(nodes), generate_subscripts(nodes, 1) from planet_osm_ways;

*/
drop table if exists way_nodes;	
with way_nodes as (
	select id as way_id, unnest(nodes) as node_id, generate_subscripts(nodes, 1) as node_nr from planet_osm_ways
)
select wn.node_id, array_agg(wn.way_id) from way_nodes wn
	join node_geometry ng on ng.node_Id = wn.node_id
	where not exists (select * from power_station s where st_intersects(s.area, ng.point))
	group by wn.node_id
	having count(*) > 2 limit 5;