begin;
drop table if exists redundant_joints;
create table redundant_joints (
    station_id   varchar(64),
    line_id      varchar(64) array,
    connected_id varchar(64) array,
    primary key (station_id)
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

/* very much faster than the other one */
select j.station_id,
	array((select line_id from topology_edges e where e.line_id = any(j.line_id) and j.connected_id[1] = any(e.station_id))),
	array((select line_id from topology_edges e where e.line_id = any(j.line_id) and j.connected_id[2] = any(e.station_id))),
        j.connected_id
	from redundant_joints j; /* where array_length(jline_id, 1) > 1 */
/* but this one ensures that we're having both of them */
select j.station_id, array_agg(l.line_id), array_agg(r.line_id), j.connected_id
	from redundant_joints j
	join topology_edges l on l.line_id = any(j.line_id) and j.connected_id[1] = any(l.station_id)
	join topology_edges r on r.line_id = any(j.line_id) and j.connected_id[2] = any(r.station_id)
	group by j.station_id limit 100;

commit;
