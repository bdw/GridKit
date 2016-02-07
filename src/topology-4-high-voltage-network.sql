begin;
drop table if exists high_voltage_nodes cascade;
drop table if exists high_voltage_edges cascade;

create table high_voltage_nodes (
    station_id varchar(64)
);

create table high_voltage_edges (
    line_id varchar(64),
    left_id varchar(64),
    right_id varchar(64)
);

with recursive high_voltage_stations (osm_id) as (
    select n.station_id from topology_nodes n
        join electrical_properties p on p.osm_id = n.station_id
        where 220000 <= any(p.voltage) and (not 16.7 = all(p.frequency) or p.frequency is null)

        union

   select unnest(station_id) from topology_edges e
        join electrical_properties p on p.osm_id = e.line_id
        where 220000 <= any(p.voltage) and (not 16.7 = all(p.frequency) or p.frequency is null)

        union

   select station_id from (
       select line_id, unnest(station_id) from topology_edges e
           join high_voltage_stations h on array[h.osm_id] <@ e.station_id
   ) f (line_id, station_id)
      join electrical_properties l on l.osm_id = f.line_id
      join electrical_properties s on s.osm_id = f.station_id
       where (not 220000 > all(l.voltage) or l.voltage is null)
         and (not 16.7 = all(l.frequency) or l.frequency is null)
         and (not 220000 > all(s.voltage) or s.voltage is null)
         and (not 16.7 = all(s.frequency) or s.frequency is null)

) insert into high_voltage_nodes (station_id)
       select * from high_voltage_stations;

insert into high_voltage_edges (line_id, left_id, right_id)
       select line_id, a.station_id, b.station_id from topology_edges e
              join high_voltage_nodes a on a.station_id = e.station_id[1]
              join high_voltage_nodes b on b.station_id = e.station_id[2];
commit;
