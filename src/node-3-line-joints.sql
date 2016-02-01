begin;
drop table if exists shared_nodes_joint;
drop table if exists node_joint_lines;
drop table if exists node_split_lines;

create table shared_nodes_joint (
    node_id varchar(64),
    objects text[],
    location geometry(point,3857)
);

create table node_joint_lines (
    source_id varchar(64),
    extent    geometry(linestring, 3857),
    nodes     geometry(multipolygon, 3857)
);

create table node_split_lines (
    synth_id varchar(64),
    source_id varchar(64),
    segment   geometry(linestring, 3857),
    nodes     geometry(multipolygon, 3857)
);

insert into shared_nodes_joint (node_id, objects, location)
    select concat('n', s.node_id), s.way_id, n.point
        from shared_nodes s
        join node_geometry n on n.node_id = s.node_id
        where 'l' = all(power_type) and (
            array_length(way_id, 1) > 2 or (
                path_idx[1] not in (0, 1) or
                path_idx[2] not in (0, 1)
            )
        );

/* remove overlap with station */
delete from shared_nodes_joint j where exists (select * from power_station s where st_intersects(s.area, j.location));

insert into node_joint_lines (source_id, extent, nodes)
    select osm_id, extent, st_multi(st_buffer(st_union(location), 1))
        from power_line l join shared_nodes_joint j on l.osm_id = any(j.objects)
        group by osm_id, extent;

insert into node_split_lines (synth_id, source_id, segment, nodes)
    select concat('ns', nextval('synthetic_objects')), source_id,
           (st_dump(st_difference(extent, nodes))).geom, nodes
           from node_joint_lines;

insert into power_line (osm_id, power_name, tags, extent, terminals, objects)
    select s.synth_id, l.power_name, l.tags, s.segment,
           minimal_terminals(s.segment, s.nodes, l.terminals),
           source_line_objects(array[source_id])
        from node_split_lines s join power_line l on l.osm_id = s.source_id;

insert into power_station (osm_id, power_name, objects, location, area)
    select node_id, 'joint', objects, location, st_buffer(location, 1)
        from shared_nodes_joint;

delete from power_line where osm_id in (select source_id from node_joint_lines);

commit;
