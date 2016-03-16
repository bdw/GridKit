/* assume we use the osm2pgsql 'accidental' tables */
begin transaction;

drop table if exists node_geometry;
drop table if exists way_geometry;
drop table if exists relation_member;
drop table if exists power_type_names;
drop table if exists electrical_properties;
drop table if exists power_station;
drop table if exists power_line;
drop table if exists osm_ids;
drop table if exists osm_tags;
drop table if exists osm_objects;
drop sequence if exists line_id;
drop sequence if exists station_id;


create sequence station_id;
create sequence line_id;

create table node_geometry (
    node_id bigint primary key,
    point   geometry(point, 3857)
);

create table way_geometry (
    way_id bigint primary key,
    line   geometry(linestring, 3857)
);

create table osm_ids (
    osm_name varchar(64) primary key,
    osm_id   bigint not null,
    osm_type char(1) not null,
    power_id integer not null,
    power_type char(1) not null
);

create table osm_tags (
    osm_name varchar(64) primary key,
    tags    hstore
);

create table osm_objects (
    power_id integer,
    power_type char(1),
    objects  varchar(64) array not null,
    primary key (power_id, power_type)
);

/* lookup table for power types */
create table power_type_names (
    power_name varchar(64) primary key,
    power_type char(1) not null,
    check (power_type in ('s','l','r', 'v'))
);

create table relation_member (
    relation_id bigint,
    member_id   varchar(64) not null,
    member_role varchar(64) null
);

create table electrical_properties (
    power_id integer,
    power_type char(1),
    frequency float array,
    voltage int array,
    conductor_bundles int array,
    subconductors int array,
    power_name varchar(64),
    operator text,
    name text,
    primary key (power_id, power_type)
);


create table power_station (
    station_id integer primary key,
    power_name varchar(64) not null,
    location geometry(point, 3857),
    area geometry(polygon, 3857)
);

create table power_line (
    line_id integer primary key,
    power_name varchar(64) not null,
    extent    geometry(linestring, 3857),
    terminals geometry(geometry, 3857)
);


/* all things recognised as certain stations */
insert into power_type_names (power_name, power_type)
    values ('station', 's'),
           ('substation', 's'),
           ('sub_station', 's'),
           ('plant', 's'),
           ('cable', 'l'),
           ('line', 'l'),
           ('minor_cable', 'l'),
           ('minor_line', 'l'),
           -- virtual elements
           ('merge', 'v'),
           ('joint', 'v');


/* we could read this out of the planet_osm_point table, but i'd
 * prefer calculating under my own control */
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


/* TODO: figure out how to compute relation geometry, given that it
   may be recursive! */
insert into relation_member (relation_id, member_id, member_role)
    select s.pid, s.mid, s.mrole from (
        select id as pid, unnest(akeys(hstore(members))) as mid,
                    unnest(avals(hstore(members))) as mrole
              from planet_osm_rels
    ) s;

-- identify objects as lines or stations
insert into osm_ids (osm_id, osm_type, osm_name, power_id, power_type)
    select id, 'n', concat('n', id), nextval('station_id'), 's'
        from planet_osm_nodes n
        join power_type_names t
        on hstore(n.tags)->'power' = t.power_name
        and t.power_type = 's';

insert into osm_ids (osm_id, osm_type, osm_name, power_id, power_type)
    select id, 'w', concat('w', id), nextval('station_id'), 's'
        from planet_osm_ways n
        join power_type_names t
        on hstore(n.tags)->'power' = t.power_name
        and t.power_type = 's';

insert into osm_ids (osm_id, osm_type, osm_name, power_id, power_type)
    select id, 'w', concat('w', id), nextval('line_id'), 'l'
        from planet_osm_ways n
        join power_type_names t
        on hstore(n.tags)->'power' = t.power_name
        and t.power_type = 'l';

insert into power_station (station_id, power_name, location, area)
     select i.power_id, hstore(n.tags)->'power', ng.point, buffered_station_point(ng.point)
          from osm_ids i
          join planet_osm_nodes n on n.id = i.osm_id
          join node_geometry ng on  ng.node_id = i.osm_id
          where i.power_type = 's' and i.osm_type = 'n';

insert into power_station (station_id, power_name, location, area)
     select i.power_id, hstore(w.tags)->'power',
            st_centroid(wg.line),
            buffered_station_area(way_station_area(wg.line))
          from osm_ids i
          join planet_osm_ways w on w.id = i.osm_id
          join way_geometry wg   on wg.way_id = i.osm_id
          where i.power_type = 's' and i.osm_type = 'w';

insert into power_line (line_id, power_name, extent, terminals)
    select i.power_id, hstore(w.tags)->'power', wg.line, buffered_terminals(wg.line)
        from osm_ids i
        join planet_osm_ways w on w.id = i.osm_id
        join way_geometry wg on wg.way_id = i.osm_id
        where i.power_type = 'l';

-- setup object and tag tracking
insert into osm_tags (osm_name, tags)
    select i.osm_name, hstore(n.tags)
        from osm_ids i
        join planet_osm_nodes n on n.id = i.osm_id
        where i.osm_type = 'n';

insert into osm_tags (osm_name, tags)
    select i.osm_name, hstore(w.tags)
           from osm_ids i
           join planet_osm_ways w on w.id = i.osm_id
           where i.osm_type = 'w';

insert into osm_objects (power_id, power_type, objects)
     select power_id, power_type, array[osm_name]
         from osm_ids;
commit;
