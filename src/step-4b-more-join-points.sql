begin;
drop table if exists line_terminals;
drop table if exists line_intersections;
create table line_terminals (
       osm_id varchar(64),
       area geometry(polygon, 3857)
);
create table line_intersections (
       id serial primary key,
       src varchar(64),
       dst varchar(64),
       area geometry(polygon, 3857)
);
insert into line_terminals (osm_id, area)
       select osm_id, (ST_Dump(terminals)).geom from power_line;
create index line_terminals_area on line_terminals using gist (area);

insert into line_intersections (src, dst, area)
       select a.osm_id, b.osm_id, ST_Buffer((ST_Dump(ST_Intersection(a.area, b.area))).geom, 1)
              from line_terminals a join line_terminals b on st_intersects(a.area, b.area)
                   and a.osm_id != b.osm_id
              where not exists (
                    select * from power_station s where st_intersects(a.area, s.area)
              );
create index line_intersection_area on line_intersections using gist (area);

commit;
