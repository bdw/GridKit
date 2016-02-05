begin;
drop table if exists redundant_joints;
drop table if exists redundant_splits;
drop table if exists simplified_splits;
drop table if exists replaced_edges;
drop table if exists removed_nodes;
drop table if exists removed_edges;
drop function if exists array_replace(anyarray, anyarray, anyarray);
drop function if exists array_sym_diff(anyarray, anyarray);

create function array_replace(a anyarray, b anyarray, n anyarray) returns anyarray as $$
begin
    return array((select unnest(a) except select unnest(b) union select unnest(n)));
end;
$$ language plpgsql;

drop function if exists array_sym_diff(anyarray, anyarray);
create function array_sym_diff(a anyarray, b anyarray) returns anyarray as $$
begin
    return array(((select unnest(a) union select unnest(b))
                   except
                  (select unnest(a) intersect select unnest(b))));
end;
$$ language plpgsql;

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

create table joint_line_pair (
    joint_id varchar(64),
    left_id varchar(64),
    right_id varchar(64)
);

create table joint_line_set (
    v varchar(64) primary key,
    k varchar(64),
    s varchar(64) array[2] -- stations
    e geometry(linestring, 3857),
);
create index joint_line_set_k on joint_line_set (k);

create table joint_merged_edges (
    synth_id   varchar(64),
    extent     geometry(linestring),
    station_id varchar(64) array[2],
    source_id  varchar(64) array,
    joint_id   varchar(64) array
);

create table replaced_edges (
    station_id varchar(64) primary key,
    old_id     varchar(64) array,
    new_id     varchar(64) array
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

/* detect redundant splits, much faster than join-group one */
insert into redundant_splits (joint_id, left_station_id, right_station_id, left_line_id, right_line_id, left_avg_length, right_avg_length)
       select j.station_id, j.connected_id[1], j.connected_id[2],
              array((select line_id from topology_edges e where e.line_id = any(j.line_id) and j.connected_id[1] = any(e.station_id))),
              array((select line_id from topology_edges e where e.line_id = any(j.line_id) and j.connected_id[2] = any(e.station_id))),
              (select avg(st_length(line_extent)) from topology_edges e where e.line_id = any(j.line_id) and j.connected_id[1] = any(e.station_id)),
              (select avg(st_length(line_extent)) from topology_edges e where e.line_id = any(j.line_id) and j.connected_id[2] = any(e.station_id))
              from redundant_joints j
              where array_length(connected_id, 1) = 2 and array_length(line_id, 1) > 2;

/* simplify split lines if possible  */
with simplification_candidates (joint_id, source_id, station_id, distortion, full_length, original_extents, simplified_extent) as (
    select joint_id, left_line_id, left_station_id, abs(st_distance(j.location, s.area) - left_avg_length), left_avg_length + right_avg_length,
        (select st_multi(st_union(extent)) from power_line where osm_id = any(left_line_id)), st_shortestline(j.area, s.area)
        from redundant_splits r
        join power_station j on j.osm_id = joint_id
        join power_station s on s.osm_id = left_station_id
        where array_length(left_line_id, 1) > 1
    union all
    select joint_id, right_line_id, right_station_id, abs(st_distance(j.location, s.area) - right_avg_length), left_avg_length + right_avg_length,
        (select st_multi(st_union(extent)) from power_line where osm_id = any(right_line_id)), st_shortestline(j.area, s.area)
        from redundant_splits r
        join power_station j on j.osm_id = joint_id
        join power_station s on s.osm_id = right_station_id
        where array_length(right_line_id, 1) > 1
)
insert into simplified_splits (synth_id, joint_id, source_id, station_id, original_extents, simplified_extent)
    select concat('y', nextval('synthetic_objects')), joint_id, source_id, station_id, original_extents, simplified_extent
        from simplification_candidates where distortion < 300 and (distortion < 100 or distortion/full_length <= 0.05);

-- replace split lines by their simplified variants
insert into power_line (osm_id, power_name, objects, extent, terminals)
     select synth_id, 'simplified', source_line_objects(source_id), simplified_extent,
            st_buffer(st_union(st_startpoint(simplified_extent), st_endpoint(simplified_extent)), 1)
            from simplified_splits;
delete from power_line where osm_id in (select unnest(source_id) from simplified_splits);

-- also replace edges
insert into replaced_edges (station_id, old_id, new_id)
    select station_id, array_agg(distinct source_id), array_agg(distinct synth_id) from (
        select joint_id, synth_id, unnest(source_id) from simplified_splits
        union
        select station_id, synth_id, unnest(source_id) from simplified_splits
    ) f (station_id, synth_id, source_id) group by station_id;
-- create new edges to replace the old ones
insert into topology_edges (line_id, station_id, line_extent, station_locations)
    select synth_id, array[joint_id, station_id], simplified_extent, array[j.location, s.location]
        from simplified_splits
        join power_station j on j.osm_id = joint_id
        join power_station s on s.osm_id = station_id;

delete from topology_edges where line_id in (select unnest(old_id) from replaced_edges);

update topology_nodes n set line_id = array_replace(n.line_id, r.old_id, r.new_id)
       from replaced_edges r where r.station_id = n.station_id;

update redundant_joints j set line_id = array_replace(j.line_id, r.old_id, r.new_id)
       from replaced_edges r where r.station_id = j.station_id;

-- create pairs out of simple joints
insert into joint_line_pair (joint_id, left_id, right_id)
    select station_id, least(line_id[1], line_id[2]), greatest(line_id[1], line_id[2])
        from redundant_joints
        where array_length(connected_id, 1) = 2 and array_length(line_id, 1) = 2;

insert into joint_line_set (k, v, e, s)
    select line_id, line_id, line_extent, station_id from topology_edges where line_id in (
        select unnest(line_id) from redundant_joints
    );

do $$
declare
    p joint_line_pair;
    l joint_line_set;
    r joint_line_set;
begin
    for p in select * from joint_line_pair loop
        select * into l from joint_line_set where v = p.left_id;
        select * into r from joint_line_set where v = p.right_id;
        if l.k != r.k then
            update joint_line_set set k = l.k where k = r.k;
            update joint_line_set
               set e = connect_lines(l.e, r.e),
                   s = array_sym_diff(l.s, r.s)
               where k = l.k;
        end if;
    end loop;
end;
$$ language plpgsql;


-- replace lines



-- also remove dangling joints
insert into removed_nodes (station_id)
    select station_id from redundant_joints where array_length(connected_id, 1) = 1;

insert into removed_edges (line_id)
    select distinct line_id from topology_edges e join removed_nodes n on n.station_id = any(e.station_id)
        union
    select distinct unnest(source_id) from simplified_splits;


-- remove nodes, maybe make this a procedure?
delete from topology_nodes where station_id in (select station_id from removed_nodes);

delete from topology_edges where line_id in (select line_id from removed_edges);
update topology_nodes n set line_id = array_remove(n.line_id, e.line_id)
    from removed_edges e where e.line_id = any(n.line_id);

select 1/0;
commit;
