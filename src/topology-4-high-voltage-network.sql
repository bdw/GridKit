begin;
drop table if exists high_voltage_nodes cascade;
drop table if exists high_voltage_edges cascade;

create table high_voltage_nodes (
    station_id integer primary key
);

create table high_voltage_edges (
    line_id integer primary key,
    left_id integer,
    right_id integer
);

with recursive high_voltage_stations (station_id) as (
    select n.station_id from topology_nodes n
        join electrical_properties p on p.power_id = n.station_id and p.power_type = 's'
        where 220000 <= any(p.voltage) and (not 16.7 = all(p.frequency) or p.frequency is null)

        union

   select unnest(e.station_id) from topology_edges e
        join electrical_properties p on p.power_id = e.line_id and p.power_type = 'l'
        where 220000 <= any(p.voltage) and (not 16.7 = all(p.frequency) or p.frequency is null)

        union

   select station_id from (
       select line_id, unnest(e.station_id) from topology_edges e
           join high_voltage_stations h on array[h.station_id] <@ e.station_id
   ) f (line_id, station_id)
      join electrical_properties l on l.power_id = f.line_id    and l.power_type = 's'
      join electrical_properties s on s.power_id = f.station_id and s.power_type = 'l'
       where (not 220000 > all(l.voltage) or l.voltage is null)
         and (not 16.7 = all(l.frequency) or l.frequency is null)
         and (not 220000 > all(s.voltage) or s.voltage is null)
         and (not 16.7 = all(s.frequency) or s.frequency is null)
) insert into high_voltage_nodes (station_id)
       select station_id from high_voltage_stations;

insert into high_voltage_edges (line_id, left_id, right_id)
       select line_id, a.station_id, b.station_id from topology_edges e
              join high_voltage_nodes a on a.station_id = e.station_id[1]
              join high_voltage_nodes b on b.station_id = e.station_id[2];
commit;
