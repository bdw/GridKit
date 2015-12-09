/* assume we use the osm2pgsql 'accidental' tables */
begin transaction;

/* compute geometries of nodes, ways */
drop table if exists node_geometry;
create table node_geometry (
       node_id bigint,
       point   geometry(point)
);

insert into node_geometry (node_id, point)
       select id, st_setsrid(st_makepoint(lon, lat), 4326)
              from planet_osm_nodes;

/* intermediary, stupid table, but it makes further computations
   so much simpler */
drop table if exists way_nodes;
create table way_nodes (
       way_id bigint,
       node_id bigint,
       order_nr int
);

/* postgresql! yay! */
insert into way_nodes (way_id, node_id, order_nr)
       select id, unnest(nodes), generate_subscripts(nodes, 1)
              from planet_osm_ways;

drop table if exists way_geometry;
create table way_geometry (
       way_id bigint,
       line   geometry(linestring)
);

insert into way_geometry
       select id, st_makeline(array_agg(n.point order by ng.order_nr))
              from planet_osm_ways w
              /* nb - does the following line keep the node order? */
              join way_nodes ng on ng.way_id = w.id
              join node_geometry n on ng.node_id = n.node_id
              group by id;

drop table if exists relation_member;
create table relation_member (
       relation_id bigint,
       member_type char(1) not null,
       member_id bigint not null,
       member_role varchar(64) null,
       foreign key (relation_id) references planet_osm_rels (id)
);

/* TODO: figure out how to compute relation geometry, given that it
   may be recursive! */
insert into relation_member (relation_id, member_type, member_id, member_role)
       select s.pid, substring(s.mid, 1, 1),
                     substring(s.mid, 2)::bigint, s.mrole from (
              select id as pid, unnest(akeys(hstore(members))) as mid,
                                unnest(avals(hstore(members))) as mrole
                    from planet_osm_rels
       ) s;


/* lookup table for power types */
drop table if exists power_type_names;

create table power_type_names (
       power_name VARCHAR(64) PRIMARY KEY,
       power_type CHAR(1) NOT NULL,
       CHECK (power_type in ('s','l','r'))
);

insert into power_type_names (power_name, power_type)
       values ('station', 's'),
              ('substation', 's'),
              ('sub_station', 's'),
              ('generator', 's'),
              ('plant', 's'),
              ('cable', 'l'),
              ('line', 'l'),
              ('minor_cable', 'l'),
              ('minor_line', 'l');


drop table if exists electrical_properties;

create table electrical_properties (
       osm_id bigint not null,
       osm_type char (1),
       part_nr int default 0,
       frequency float null,
       voltage int null,
       wires int null,
       cables int null,
       check (osm_type in ('w','l','r'))
);

drop index if exists power_station_location;
drop table if exists power_station;

create table power_station (
       osm_id bigint,
       osm_type char(1) not null,
       power_name varchar(64) not null,
       tags hstore,
       location geometry,
       primary key (osm_id, osm_type),
       check (osm_type in ('n','w','r'))
);


insert into power_station (
       osm_id, osm_type, power_name, tags, location
) select id, 'n', hstore(tags)->'power', hstore(tags), g.point
           from planet_osm_nodes n
           join node_geometry g on g.node_id = n.id
           where hstore(tags)->'power' in (
               select power_name from power_type_names
                      where power_type = 's'
         );

insert into power_station (
       osm_id, osm_type, power_name, tags, location
) select id, 'w', hstore(tags)->'power', hstore(tags),
         case when St_IsClosed(g.line)
              then St_MakePolygon(g.line)
              else g.line end
         from planet_osm_ways w
         join way_geometry g on g.way_id = w.id
         where hstore(tags)->'power' in (
               select power_name from power_type_names
                      where power_type = 's'
         );

drop index if exists power_line_extent;
drop table if exists power_line;
create table power_line (
       osm_id bigint,
       osm_type char(1) not null,
       power_name varchar(64) not null,
       tags hstore,
       extent geometry,
       primary key (osm_id, osm_type),
       check (osm_type in ('w','r'))
);




insert into power_line (
       osm_id, osm_type, power_name, tags, extent
) select id, 'w', hstore(tags)->'power', hstore(tags), g.line
         from planet_osm_ways w
         join way_geometry g on g.way_id = w.id
         where hstore(tags)->'power' in (
               select power_name from power_type_names where power_type = 'l'
         );

/* not necessary if we're going to use buffered versions of the
   geometries; nb that for buffering it might be quite a good idea to
   translate to a meter-based geometry system anyway, or to a
   geography system. */

create index power_station_location on power_station using gist(location);
create index power_line_extent on power_line using gist(extent);
commit;

/* speed up queries even further !!!!! */
vacuum analyze power_line;
vacuum analyze power_station;
