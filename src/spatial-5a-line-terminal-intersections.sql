begin;
drop table if exists line_terminals;
drop table if exists terminal_intersections;

create table line_terminals (
    terminal_id serial primary key,
    line_id integer not null,
    area geometry(polygon, 3857)
);

create table terminal_intersections (
    intersection_id serial primary key,
    src integer not null,
    dst integer not null,
    area geometry(polygon, 3857)
);

insert into line_terminals (line_id, area)
    select line_id, (ST_Dump(terminals)).geom from power_line;

create index line_terminals_area on line_terminals using gist (area);

insert into terminal_intersections (src, dst, area)
    select distinct least(a.terminal_id, b.terminal_id), greatest(a.terminal_id, b.terminal_id),
            ST_Buffer((ST_Dump(ST_Intersection(a.area, b.area))).geom, 1)
       from line_terminals a
           join line_terminals b on st_intersects(a.area, b.area) and a.line_id != b.line_id
       where not exists (
           select 1 from power_station s where st_intersects(a.area, s.area)
       );

create index terminal_intersection_src on terminal_intersections (src);
create index terminal_intersection_dst on terminal_intersections (dst);
commit;
