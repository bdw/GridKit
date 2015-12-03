/* assume we use the osm2pgsql 'accidental' tables */
drop table if exists relation_member;
create table relation_member (
       relation_id BIGINT,
       member_type CHAR(1) NOT NULL,
       member_id BIGINT NOT NULL,
       member_role VARCHAR(64) NULL,
       FOREIGN KEY (relation_id) REFERENCES planet_osm_rels
);

insert into relation_member (relation_id, member_type, member_id, member_role)
       select s.pid, substring(s.mid, 1, 1), substring(s.mid, 2)::bigint, s.mrole from (
       	      select id as pid, unnest(akeys(hstore(members))) as mid,
	      	     	   	unnest(avals(hstore(members))) as mrole
	      	     from planet_osm_rels
       ) s;

copy (
     select member_role, count(*) from relation_member group by member_role
) to '/home/bart/Data/power-rels-members.csv' with csv header;


drop table if exists station_names;
create table station_names (
       power_name VARCHAR(64) NOT NULL,
       PRIMARY KEY (power_name)
);

insert into station_names (power_name)
       values ('station'),
       	      ('substation'),
	      ('sub_station'),
	      ('generator'),
	      ('plant');

drop table if exists power_station;
create table power_station (
       osm_id BIGINT,
       osm_type CHAR(1) NOT NULL,
       power_name VARCHAR(64) NOT NULL,
       tags HSTORE,
       location GEOMETRY,
       PRIMARY KEY (osm_id, osm_type)
);



alter table planet_osm_nodes drop column if exists _point;
/* cache points */
alter table planet_osm_nodes add column _point geometry;
update planet_osm_nodes set _point = St_SetSRID(St_MakePoint(lon, lat), 4326);

/* circularity test */
alter table planet_osm_ways drop column if exists _line;
alter table planet_osm_ways add column _line geometry;
update planet_osm_ways set _line = (
       select st_makeline(array_agg(n._point)) from
       	      planet_osm_nodes n
	      join (select id as way_id, unnest(nodes) as node_id) w
	      	   on n.id = w.node_id
	      group by w.way_id
);

insert into power_station (
       osm_id, osm_type, power_name, tags, location
) select id, 'n', hstore(tags)->'power', hstore(tags), _point
  	 from planet_osm_nodes
  	 where hstore(tags)->'power' in (select power_name from station_names);



drop table if exists line_names;
create table line_names (
       line_name VARCHAR(64) NOT NULL,
       PRIMARY KEY (line_name)
);

insert into line_names (line_name)
       values ('cable'),
       	      ('line'),
	      ('minor_cable'),
	      ('minor_line');

