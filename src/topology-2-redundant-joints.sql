begin;
drop table if exists redundant_joints;
drop table if exists simplified_split_lines;
drop table if exists removed_nodes;
drop table if exists removed_edges;
drop function if exists simplification_distortion(geometry, geometry array, geometry);

create function simplification_distortion(point geometry, lines geometry array, area geometry) returns float
       as $$
declare
    simple_line geometry(linestring);
    avg_length  float;
begin
    simple_line = st_shortestline(point, area);
    avg_length  = avg((select st_length(e) from (select unnest(lines) as e) f));
    return abs(st_length(simple_line) - avg_length);
end;
$$ language plpgsql;


create table redundant_joints (
    station_id   varchar(64),
    line_id      varchar(64) array,
    connected_id varchar(64) array,
    primary key (station_id)
);

create table simplified_split_lines (
    joint_id varchar(64),
    station_id varchar(64),
    line_id varchar(64) array,
    joint_location geometry(point, 3857),
    station_area   geometry(polygon, 3857),
    line_extents   geometry(linestring, 3857) array,
    replacement    geometry(linestring, 3857)
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
/*
select j.station_id, j.connected_id
        array((select line_id from topology_edges e where e.line_id = any(j.line_id) and j.connected_id[1] = any(e.station_id))) as left_id,
        array((select line_id from topology_edges e where e.line_id = any(j.line_id) and j.connected_id[2] = any(e.station_id))) as right_id,
        from redundant_joints j where array_length(connected_id, 1) = 2;
*/


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
