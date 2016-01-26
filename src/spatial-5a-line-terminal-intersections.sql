begin;
drop table if exists line_terminals;
drop table if exists terminal_intersections;
create table line_terminals (
    id serial primary key,
    osm_id varchar(64),
    area geometry(polygon, 3857)
);
create table terminal_intersections (
    id serial primary key,
    src integer,
    dst integer,
    area geometry(polygon, 3857)
);
insert into line_terminals (osm_id, area)
    select osm_id, (ST_Dump(terminals)).geom from power_line;
create index line_terminals_area on line_terminals using gist (area);

insert into terminal_intersections (src, dst, area)
    select distinct least(a.id, b.id), greatest(a.id, b.id),
            ST_Buffer((ST_Dump(ST_Intersection(a.area, b.area))).geom, 1)
       from line_terminals a
           join line_terminals b on st_intersects(a.area, b.area) and a.osm_id != b.osm_id
       where not exists (
           select * from power_station s where st_intersects(a.area, s.area)
       );

create index terminal_intersection_src on terminal_intersections (src);
create index terminal_intersection_dst on terminal_intersections (dst);
commit;
