begin;
drop table if exists shared_nodes_joint;
create table shared_nodes_joint (
    node_id varchar(64),
    objects text[],
    location geometry(point,3857)
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
commit;
