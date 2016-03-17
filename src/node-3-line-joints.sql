begin;
drop table if exists shared_nodes_joint;
drop table if exists node_joint_lines;
drop table if exists node_split_lines;

create table shared_nodes_joint (
    node_id bigint primary key,
    line_id  integer array,
    location geometry(point, 3857)
);

create table node_joint_lines (
    line_id   integer primary key,
    extent    geometry(linestring, 3857),
    points    geometry(multipolygon, 3857)
);

create table node_split_lines (
    line_id   integer not null,
    source_id integer not null,
    segment   geometry(linestring, 3857),
    points    geometry(multipolygon, 3857)
);


insert into shared_nodes_joint (node_id, location, line_id)
    select s.node_id, n.point, array(
        select power_id from osm_ids i
             where i.osm_type = 'w' and i.osm_id = any(s.way_id)
        )
        from shared_nodes s
        join node_geometry n on n.node_id = s.node_id
        where 'l' = all(power_type) and (
            array_length(way_id, 1) > 2 or (
                path_idx[1] not in (0, 1) or
                path_idx[2] not in (0, 1)
            )
        ) and not exists (
            select 1 from power_station s where st_intersects(s.area, n.point)
        );

insert into node_joint_lines (line_id, extent, points)
    select g.line_id, l.extent, g.points from (
        select line_id, st_multi(st_union(st_buffer(location, 1))) from (
            select unnest(line_id), location from shared_nodes_joint
        ) f(line_id, location) group by line_id
    ) g (line_id, points)
        join power_line l on g.line_id = l.line_id;


insert into node_split_lines (line_id, source_id, segment, points)
    select nextval('line_id'), line_id,
           (st_dump(st_difference(extent, points))).geom, points
           from node_joint_lines;

-- create joints power stations, start with ids for osm id
insert into osm_ids (osm_type, osm_id, osm_name, power_type, power_id)
    select 'n', node_id, concat('n', node_id), 's', nextval('station_id')
        from shared_nodes_joint;

insert into power_station (station_id, power_name, location, area)
    select i.power_id, 'joint', j.location, st_buffer(j.location, 1)
        from shared_nodes_joint j
        join osm_ids i on i.osm_type = 'n' and i.osm_id = j.node_id;

-- source objects are combination of lines and the node itself
insert into osm_objects (power_id, power_type, objects)
    select i.power_id, 's', source_objects(line_id, 'l') || i.osm_name
           from shared_nodes_joint j
           join osm_ids i on i.osm_type = 'n' and i.osm_id = j.node_id;

-- replacement power lines
insert into power_line (line_id, power_name, extent, terminals)
    select s.line_id, l.power_name, s.segment,
           minimal_terminals(s.segment, s.points, l.terminals)
        from node_split_lines s
        join power_line l on l.line_id = s.source_id;

delete from power_line l where exists (
    select 1 from node_joint_lines j where j.line_id = l.line_id
);

commit;
