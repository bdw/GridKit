begin;
drop table if exists heuristic_links cascade;
drop table if exists heuristic_vertices cascade;
drop table if exists heuristic_vertices_highvoltage;
drop table if exists heuristic_links_highvoltage;


-- simplify to format of scigrid export
create table heuristic_vertices (
    v_id        serial primary key,
    osm_id      varchar(64),
    osm_objects varchar(64) array,
    location    geometry(point, 3857),
    typ         text,
    voltage     integer array,
    frequency   float array,
    name        text,
    operator    text,
    ref         text
);
create table heuristic_links (
    l_id        serial primary key,
    v_id_1      integer references heuristic_vertices (v_id),
    v_id_2      integer references heuristic_vertices (v_id),
    osm_id      varchar(64),
    osm_objects varchar(64) array,
    line        geometry(linestring, 3857),
    voltage     integer array,
    cables      integer array,
    wires       integer array,
    frequency   float array,
    name        text,
    operator    text,
    ref         text,
    length_m    float,
    r_ohmkm     float,
    x_ohmkm     float,
    c_nfkm      float,
    i_th_max_a  float
);

create index heuristic_vertices_osm_id on heuristic_vertices (osm_id);
create index heuristic_links_osm_id on heuristic_links (osm_id);

insert into heuristic_vertices (osm_id, osm_objects, location, typ, voltage, frequency, name, operator, ref)
    select n.station_id, o.objects, n.station_location, e.power_name, e.voltage, e.frequency, e.name, e.operator, t.tags->'ref'
           from topology_nodes n
           join electrical_properties e on e.osm_id = n.station_id
           join osm_objects o on o.osm_id = n.station_id
           join osm_tags t on t.osm_id = n.station_id;

insert into heuristic_links (v_id_1, v_id_2, osm_id, osm_objects, line, length_m, voltage, cables, wires, frequency, name, operator, ref)
    select a.v_id, b.v_id, l.line_id, o.objects, st_makeline(a.location, b.location), st_length(st_transform(l.line_extent, 4326)::geography),
           e.voltage, e.conductor_bundles, e.subconductors, e.frequency, e.name, e.operator, t.tags->'ref'
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
