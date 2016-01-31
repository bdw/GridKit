begin;
drop table if exists high_voltage_nodes;
drop table if exists high_voltage_edges;

/*
nb - can we replace this with an update? maybe if we add a boolean high_voltage field to nodes and edges

select unnest(station_id) from topology_edges t join electrical_properties e on t.line_id = e.osm_id where 220000 <= any(voltage) and not 16.7 = all(frequency)
union
select station_id from topology_nodes t join electrical_properties e on t.station_id = e.osm_id where 220000 <= any(voltage) and not 16.7 = all(frequency)

*/

with recursive high_voltage_nodes(osm_id) as (
     /* maybe find a way to UNION with nodes-of-high-voltage-edges */
    select n.osm_id from nodes n, electrical_properties p where p.osm_id = n.osm_id
            and 220000 <= any(voltage) and not 16.7 = all(frequency)
     union
     select e.osm_id from (select unnest(nodes) from edges join high_voltage_nodes n on n.osm_id = any(nodes)) e
            join electrical_properties p on p.osm_id = e.osm_id
            where not 220000 > all(p.voltage) and not 16.7 = all(frequency)
)
insert into high_voltage_nodes (osm_id)
       select * from high_voltage_nodes;
insert into high_voltage_edges (line_id, left_id, right_id)
       select line_id, left_id, right_id from edges e
              join high_voltage_nodes a on a.osm_id = e.left_id
              join high_voltage_nodes b on b.osm_id = e.right_id;
commit;
