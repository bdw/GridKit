/* assume we use the osm2pgsql 'accidental' tables */
begin transaction;
drop table if exists node_geometry;
drop table if exists way_geometry;
drop table if exists relation_member;
drop table if exists power_type_names;
drop table if exists reference_parameters;
drop table if exists electrical_properties;

drop table if exists power_station;
drop table if exists power_line;
drop table if exists power_generator;

drop table if exists source_ids;
drop table if exists source_tags;
drop table if exists source_objects;

drop sequence if exists line_id;
drop sequence if exists station_id;
drop sequence if exists generator_id;

create sequence station_id;
create sequence line_id;
create sequence generator_id;

create table node_geometry (
    node_id bigint primary key,
    point   geometry(point, 3857)
);

create table way_geometry (
    way_id bigint primary key,
    line   geometry(linestring, 3857)
);

-- implementation of source_ids and source_tags table will depend on the data source used
create table source_ids (
    source_id varchar(64) primary key,
    osm_id   bigint not null,
    osm_type char(1) not null,
    power_id integer not null,
    power_type char(1) not null
);

-- both ways lookups
create index source_ids_osm_idx   on source_ids (osm_type, osm_id);
create index source_ids_power_idx on source_ids (power_type, power_id);

create table source_tags (
    source_id varchar(64) primary key,
    tags      hstore
);

create table source_objects (
    power_id integer,
    power_type char(1),
    objects  jsonb,
    primary key (power_id, power_type)
);


/* lookup table for power types */
create table power_type_names (
    power_name varchar(64) primary key,
    power_type char(1) not null,
    check (power_type in ('s','l','g', 'v'))
);

create table reference_parameters (
    voltage integer primary key,
    wires   integer not null,
    r_ohmkm float not null,
    x_ohmkm float not null,
    c_nfkm  float not null,
    i_th_max_a float not null
);


create table relation_member (
    relation_id bigint,
    member_id   varchar(64) not null,
    member_role varchar(64) null
);

create table power_station (
    station_id integer primary key,
    power_name varchar(64) not null,
    location geometry(point, 3857),
    area geometry(polygon, 3857)
);

create index power_station_area_idx on power_station using gist (area);

create table power_line (
    line_id integer primary key,
    power_name varchar(64) not null,
    extent    geometry(linestring, 3857),
    radius    integer array[2]
);

create index power_line_extent_idx on power_line using gist(extent);
create index power_line_startpoint_idx on power_line using gist(st_startpoint(extent));
create index power_line_endpoint_idx on power_line using gist(st_endpoint(extent));


create table power_generator (
    generator_id integer primary key,
    osm_id bigint,
    osm_type char(1),
    geometry geometry(geometry, 3857),
    location geometry(point, 3857),
    tags hstore
);

create index power_generator_location_idx on power_generator using gist(location);

-- all things recognised as power objects
insert into power_type_names (power_name, power_type)
    values ('station', 's'),
           ('substation', 's'),
           ('sub_station', 's'),
           ('plant', 's'),
           ('cable', 'l'),
           ('line', 'l'),
           ('minor_cable', 'l'),
           ('minor_line', 'l'),
           ('minor_undeground_cable', 'l'),
           ('generator', 'g'),
           ('gas generator', 'g'),
           ('wind generator', 'g'),
           ('hydro', 'g'),
           ('hydroelectric', 'g'),
           ('heliostat', 'g'),
           -- virtual elements
           ('merge', 'v'),
           ('joint', 'v');


insert into reference_parameters (voltage, wires, r_ohmkm, x_ohmkm, c_nfkm, i_th_max_a)
    -- taken from scigrid, who took them from DENA, who took them from... ?
    values (220000, 2, 0.080, 0.32, 11.5, 1.3),
           (380000, 4, 0.025, 0.25, 13.7, 2.6);


-- we could read this out of the planet_osm_point table, but i'd
-- prefer calculating under my own control.
insert into node_geometry (node_id, point)
    select id, st_setsrid(st_makepoint(lon/100.0, lat/100.0), 3857)
        from planet_osm_nodes;

insert into way_geometry (way_id, line)
    select way_id, ST_MakeLine(n.point order by order_nr)
        from (
             select id as way_id, unnest(nodes) as node_id, generate_subscripts(nodes, 1) as order_nr
                 from planet_osm_ways
        ) as wn
        join node_geometry n on n.node_id = wn.node_id
        group by way_id;


-- TODO: figure out how to compute relation geometry, given that it
-- may be recursive
insert into relation_member (relation_id, member_id, member_role)
    select s.pid, s.mid, s.mrole from (
        select id as pid, unnest(akeys(hstore(members))) as mid,
                    unnest(avals(hstore(members))) as mrole
              from planet_osm_rels
    ) s;

-- identify objects as lines or stations
insert into source_ids (osm_id, osm_type, source_id, power_id, power_type)
    select id, 'n', concat('n', id), nextval('station_id'), 's'
        from planet_osm_nodes n
        join power_type_names t
        on hstore(n.tags)->'power' = t.power_name
        and t.power_type = 's';

insert into source_ids (osm_id, osm_type, source_id, power_id, power_type)
    select id, 'w', concat('w', id), nextval('station_id'), 's'
        from planet_osm_ways n
        join power_type_names t
        on hstore(n.tags)->'power' = t.power_name
        and t.power_type = 's';

insert into source_ids (osm_id, osm_type, source_id, power_id, power_type)
    select id, 'w', concat('w', id), nextval('line_id'), 'l'
        from planet_osm_ways n
        join power_type_names t
        on hstore(n.tags)->'power' = t.power_name
        and t.power_type = 'l';

insert into power_generator (generator_id, osm_id, osm_type, geometry, location, tags)
     select nextval('generator_id'), id, 'n', ng.point, ng.point, hstore(n.tags)
       from planet_osm_nodes n
       join node_geometry ng on ng.node_id = n.id
       join power_type_names t on hstore(tags)->'power' = t.power_name
        and t.power_type = 'g';

insert into power_generator (generator_id, osm_id, osm_type, geometry, location, tags)
     select nextval('generator_id'), id, 'w',
            case when st_isclosed(wg.line) then st_makepolygon(wg.line)
                 else wg.line end,
            st_centroid(wg.line), hstore(w.tags)
       from planet_osm_ways w
       join way_geometry wg on wg.way_id = w.id
       join power_type_names t on hstore(tags)->'power' = t.power_name
        and t.power_type = 'g';

insert into power_station (station_id, power_name, location, area)
     select i.power_id, hstore(n.tags)->'power', ng.point, buffered_station_point(ng.point)
       from source_ids i
       join planet_osm_nodes n on n.id = i.osm_id
       join node_geometry ng on  ng.node_id = i.osm_id
      where i.power_type = 's' and i.osm_type = 'n';

insert into power_station (station_id, power_name, location, area)
     select i.power_id, hstore(w.tags)->'power',
            st_centroid(wg.line),
            buffered_station_area(way_station_area(wg.line))
          from source_ids i
          join planet_osm_ways w on w.id = i.osm_id
          join way_geometry wg   on wg.way_id = i.osm_id
          where i.power_type = 's' and i.osm_type = 'w';

insert into power_line (line_id, power_name, extent, radius)
    select i.power_id, hstore(w.tags)->'power', wg.line, default_radius(wg.line)
        from source_ids i
        join planet_osm_ways w on w.id = i.osm_id
        join way_geometry wg on wg.way_id = i.osm_id
        where i.power_type = 'l';

-- setup object and tag tracking
insert into source_tags (source_id, tags)
    select i.source_id, hstore(n.tags)
        from source_ids i
        join planet_osm_nodes n on n.id = i.osm_id
        where i.osm_type = 'n';

insert into source_tags (source_id, tags)
     select i.source_id, hstore(w.tags)
       from source_ids i
       join planet_osm_ways w on w.id = i.osm_id
      where i.osm_type = 'w';

insert into source_objects (power_id, power_type, objects)
     select power_id, power_type, json_build_object('source', source_id)::jsonb
       from source_ids;

commit;
