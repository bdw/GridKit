begin;
drop table if exists redundant_joints;
drop table if exists redundant_splits;
drop table if exists simplified_splits;
drop table if exists removed_nodes;
drop table if exists removed_edges;


create table redundant_joints (
    station_id   varchar(64),
    line_id      varchar(64) array,
    connected_id varchar(64) array,
    primary key (station_id)
);

create table redundant_splits (
    joint_id varchar(64),
    left_station_id varchar(64),
    left_line_id varchar(64) array,
    left_avg_length float,
    right_station_id varchar(64),
    right_line_id varchar(64) array,
    right_avg_length float
);

create table simplified_splits (
    synth_id varchar(64),
    joint_id varchar(64),
    station_id varchar(64),
    source_id varchar(64) array,
    original_extents geometry(multilinestring, 3857),
    simplified_extent geometry(linestring, 3857)
);

create table removed_nodes (
    station_id varchar(64) primary key
);

create table removed_edges (
    line_id varchar(64) primary key
);


-- Collect all joint stations that connect just two stations, for they
-- are target for removal.

insert into redundant_joints (station_id, line_id, connected_id)
    select station_id, array_agg(line_id) as line_id,
           array_agg(distinct connected_id) as connected_id from (
        select n.station_id, e.line_id, unnest(e.station_id) as connected_id
            from topology_nodes n
            join topology_edges e on e.line_id = any(n.line_id)
           where n.topology_name = 'joint'
    ) f where station_id != connected_id
    group by station_id having count(distinct connected_id) <= 2;

/* very much faster than the other one */
insert into redundant_splits (joint_id, left_station_id, right_station_id, left_line_id, right_line_id, left_avg_length, right_avg_length)
       select j.station_id, j.connected_id[1], j.connected_id[2],
              array((select line_id from topology_edges e where e.line_id = any(j.line_id) and j.connected_id[1] = any(e.station_id))),
              array((select line_id from topology_edges e where e.line_id = any(j.line_id) and j.connected_id[2] = any(e.station_id))),
              (select avg(st_length(line_extent)) from topology_edges e where e.line_id = any(j.line_id) and j.connected_id[1] = any(e.station_id)),
              (select avg(st_length(line_extent)) from topology_edges e where e.line_id = any(j.line_id) and j.connected_id[2] = any(e.station_id))
              from redundant_joints j
              where array_length(connected_id, 1) = 2 and array_length(line_id, 1) > 2;

insert into simplified_lines

-- remove dangling joints
insert into removed_nodes (station_id)
    select station_id from redundant_joints where array_length(connected_id, 1) = 1;

-- remove simple joints


-- remove nodes, maybe make this a procedure?
/*
delete from topology_nodes where station_id in (select station_id from removed_nodes);
insert into removed_edges (line_id)
    select distinct line_id from topology_edges e join removed_nodes n on n.station_id = any(e.station_id);

delete from topology_edges where line_id in (select line_id from removed_edges);
update topology_nodes n set line_id = array_remove(n.line_id, e.line_id)
       from removed_edges e where e.line_id = any(n.line_id);
*/
commit;
