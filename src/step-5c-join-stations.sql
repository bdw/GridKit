begin;
drop table if exists line_joins;
create table line_joins (
       terminal_id int[],
       objects     text[],
       area        geometry(polygon, 3857)
);
insert into line_joins (terminal_id, area, objects)
    select array_agg(s.v) as terminal_id, st_union(t.area) as area,
            array_agg(distinct (select unnest(l.objects))) as objects
            from terminal_union_sets s
            join line_terminals t on t.id = s.v
            join power_line l on l.osm_id = t.osm_id
            group by s.k having count(*) > 2


insert into power_station (osm_id, power_name, objects, location, area)
       select concat('j', nextval('synthetic_objects')), 'join', objects,
              st_centroid(area), area from line_joins;
commit;
