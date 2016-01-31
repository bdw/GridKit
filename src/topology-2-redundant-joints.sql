begin;
drop table if exists redundant_joints;
create table redundant_joints (
    station_id   varchar(64),
    line_id      varchar(64) array,
    connected_id varchar(64) array
);

/* Collect all joint stations that connect just two stations, for they
 * are target for removal. */

insert into redundant_joints (station_id, line_id, connected_id)
    select station_id, array_agg(line_id) as line_id,
           array_agg(distinct connected_id) as connected_id from (
        select n.station_id, e.line_id, unnest(e.station_id) as connected_id
            from topology_nodes n
            join topology_edges e on e.line_id = any(n.line_id)
           where n.topology_name = 'joint'
    ) f where station_id != connected_id
    group by station_id having count(distinct connected_id) <= 2;
commit;
