begin;
drop table if exists heuristic_links cascade;
drop table if exists heuristic_vertices cascade;
drop table if exists heuristic_vertices_highvoltage;
drop table if exists heuristic_links_highvoltage;

-- simplify to format of scigrid export
-- v_id,lon,lat,typ,voltage,frequency,name,operator,ref,wkt_srid_4326
create table heuristic_vertices (
    v_id        serial primary key,
    lon         float,
    lat         float,
    typ         text,
    voltage     text,
    frequency   text,
    name        text,
    operator    text,
    ref         text,
    wkt_srid_4326 text,
    osm_id      varchar(64),
    osm_objects varchar(64) array,
    location    geometry(point, 3857)
);

-- l_id,v_id_1,v_id_2,voltage,cables,wires,frequency,name,operator,ref,length_m,r_ohmkm,x_ohmkm,c_nfkm,i_th_max_a,from_relation,wkt_srid_4326
create table heuristic_links (
    l_id        serial primary key,
    v_id_1      integer references heuristic_vertices (v_id),
    v_id_2      integer references heuristic_vertices (v_id),
    voltage     text,
    cables      text,
    wires       text,
    frequency   text,
    name        text,
    operator    text,
    ref         text,
    length_m    float,
    r_ohmkm     float,
    x_ohmkm     float,
    c_nfkm      float,
    i_th_max_a  float,
    from_relation text,
    wkt_srid_4326 text,
    osm_id      varchar(64),
    osm_objects varchar(64) array,
    line        geometry(linestring, 3857)
);

create index heuristic_vertices_osm_id on heuristic_vertices (osm_id);
create index heuristic_links_osm_id on heuristic_links (osm_id);


insert into heuristic_vertices (lon, lat, typ, voltage, frequency, name, operator, ref, wkt_srid_4326, osm_id, osm_objects, location)
    select ST_X(ST_Transform(station_location, 4326)), 
           ST_Y(ST_Transform(station_location, 4326)),
           n.topology_name,
           array_to_string(e.voltage, ';'),
           array_to_string(e.frequency, ';'),
           e.name,
           e.operator,
           t.tags->'ref',
           ST_AsEWKT(ST_Transform(station_location, 4326)),
           station_id,
           o.objects,
           n.station_location
           from topology_nodes n
           join electrical_properties e on e.osm_id = n.station_id
           join osm_objects o on o.osm_id = n.station_id
           join osm_tags t on t.osm_id = n.station_id;


insert into heuristic_links (v_id_1, v_id_2, length_m, voltage, cables, wires, frequency, name, operator, ref, from_relation, wkt_srid_4326, osm_id, osm_objects, line)
    select a.v_id,
           b.v_id,
           st_length(st_transform(l.line_extent, 4326)::geography),
           array_to_string(e.voltage, ';'),
           array_to_string(e.conductor_bundles, ';'),
           array_to_string(e.subconductors, ';'),
           array_to_string(e.frequency, ';'),
           e.name,
           e.operator,
           t.tags->'ref', '',
           ST_AsEWKT(ST_Transform(ST_MakeLine(a.location, b.location), 4326)),
           l.line_id,
           o.objects,
           st_makeline(a.location, b.location)
           from topology_edges l
           join electrical_properties e on e.osm_id = l.line_id
           join osm_objects o on o.osm_id = l.line_id
           join osm_tags t on t.osm_id = l.line_id
           join heuristic_vertices a on a.osm_id = l.station_id[1]
           join heuristic_vertices b on b.osm_id = l.station_id[2];

create table heuristic_vertices_highvoltage as
    select * from heuristic_vertices where osm_id in (select station_id from high_voltage_nodes);

create table heuristic_links_highvoltage as
   select * from heuristic_links where osm_id in (select line_id from high_voltage_edges);



commit;
