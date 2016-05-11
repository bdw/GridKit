begin;
drop table if exists links;
drop table if exists vertices;


create table vertices (
    v_id integer primary key,
    lon float,
    lat float,
    typ text,
    name text,
    capacity numeric,
    wkt_srid_4326 text
);

create table links (
   l_id integer primary key,
   v_id_1 integer references vertices (v_id),
   v_id_2 integer references vertices (v_id),
   name text,
   circuits integer,
   voltage text,
   frequency integer,
   cables integer,
   wires integer,
   length_m numeric,
   wkt_srid_4326 text
);

insert into vertices (v_id, lon, lat, typ, name, capacity, wkt_srid_4326)
    select n.station_id,
           ST_X(ST_Transform(station_location, 4326)),
           ST_Y(ST_Transform(station_location, 4326)),
           n.topology_name, c.name, c.capacity,
           ST_AsEWKT(ST_Transform(station_location, 4326))
      from topology_nodes n
 left join computed_station_properties c on c.station_id = n.station_id;

insert into links (l_id, v_id_1, v_id_2, name,
                  circuits, voltage, frequency, cables, wires,
                  length_m, wkt_srid_4326)
     select e.line_id, e.station_id[1], e.station_id[2], 'line',
            c.circuits, c.voltage, c.frequency,
            c.circuits * 3, -- TODO, if frequency == 0, then maybe not 3-phase
            -- approximate the wires
            case when c.voltage < 200 then 1
                 when c.voltage < 300 then 2
                 else 4 end,
            -- line lengths according to ENTSO-E are prefered... although probably inaccurate
            case when c.length_m > 0 then c.length_m
                 else st_length(st_transform(e.line_extent, 4326)::geography) end,
            st_asewkt(st_transform(line_extent, 4326))
       from topology_edges e
       join computed_line_properties c on c.line_id = e.line_id;

-- create transformer links, too
insert into links (l_id, v_id_1, v_id_2, name, voltage, frequency, wkt_srid_4326)
       select t.transformer_id, t.station_id, t.station_id, 'transformer',
              concat(t.low_voltage,';',t.high_voltage), 50,
              st_asewkt(st_transform(t.location,4326))
              from transformers t;
commit;
      
