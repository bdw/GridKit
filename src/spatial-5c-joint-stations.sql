begin;
drop table if exists line_joints;
drop table if exists joint_extended_line;
create table line_joints (
    station_id  integer,
    line_id     integer array,
    terminal_id integer array,
    area        geometry(polygon, 3857)
);

create table joint_extended_line (
    line_id integer primary key,
    station_id integer array,
    old_extent geometry(linestring, 3857),
    new_extent geometry(linestring, 3857),
    areas      geometry(multipolygon, 3857)
);

with grouped_terminals(terminal_id) as (
    select array_agg(s.v)
       from terminal_sets s
       group by s.k having count(*) > 2
) insert into line_joints (station_id, terminal_id, line_id, area)
    select nextval('station_id'), g.terminal_id,
        array(select distinct line_id from line_terminals t where t.terminal_id = any(g.terminal_id)),
        (select st_union(area) from line_terminals t where t.terminal_id = any(g.terminal_id))
        from grouped_terminals g;

insert into joint_extended_line (line_id, station_id, areas, old_extent, new_extent)
    select g.line_id, g.station_id, g.areas, l.extent, l.extent from (
        select f.line_id, array_agg(f.station_id), st_multi(st_union(f.area)) from (
            select station_id, unnest(line_id), area from line_joints
        ) f (station_id, line_id, area)
        group by f.line_id
    ) g (line_id, station_id, areas)
    join power_line l on g.line_id = l.line_id;

update joint_extended_line
   set new_extent = connect_lines(new_extent, st_shortestline(st_startpoint(new_extent), st_centroid(areas)))
   where st_contains(areas, st_startpoint(new_extent));

update joint_extended_line
   set new_extent = connect_lines(new_extent, st_shortestline(st_endpoint(new_extent), st_centroid(areas)))
      where st_contains(areas, st_endpoint(new_extent));

insert into power_station (station_id, power_name, location, area)
    select station_id, 'joint', st_centroid(area), st_buffer(st_centroid(area), 1)
        from line_joints;

insert into osm_objects (power_id, power_type, objects)
    select station_id, 's', track_objects(line_id, 'l', 'merge') from line_joints;

update power_line l
   set extent = j.new_extent,
       terminals = minimal_terminals(j.new_extent, j.areas, l.terminals)
       from joint_extended_line j where j.line_id = l.line_id;

commit;
