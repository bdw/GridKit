begin;
drop table if exists redundant_joints;
drop table if exists redundant_splits;
drop table if exists simplified_splits;
drop table if exists replaced_edges;
drop table if exists removed_nodes;
drop table if exists removed_edges;
drop table if exists joint_edge_pair;
drop table if exists joint_edge_set;
drop table if exists joint_merged_edges;
drop function if exists array_replace(anyarray, anyarray, anyarray);
drop function if exists array_sym_diff(anyarray, anyarray);

create function array_replace(a anyarray, b anyarray, n anyarray) returns anyarray as $$
begin
    return array((select unnest(a) except select unnest(b) union select unnest(n)));
end;
$$ language plpgsql;

create function array_sym_diff(a anyarray, b anyarray) returns anyarray as $$
begin
    return array(((select unnest(a) union select unnest(b))
                   except
                  (select unnest(a) intersect select unnest(b))));
end;
$$ language plpgsql;

create table redundant_joints (
    joint_id   varchar(64),
    line_id    varchar(64) array,
    station_id varchar(64) array,
    primary key (joint_id)
);

create table redundant_splits (
    line_id varchar(64) array,
    station_id varchar(64) array
);

create table simplified_splits (
    synth_id varchar(64),
    station_id varchar(64) array[2],
    source_id varchar(64) array,
    simple_extent geometry(linestring, 3857),
    original_extents geometry(multilinestring, 3857),
    distortion float
);

create table joint_edge_pair (
    joint_id varchar(64),
    left_id varchar(64),
    right_id varchar(64)
);

create table joint_edge_set (
    v varchar(64) primary key,
    k varchar(64),
    s varchar(64) array[2], -- stations
    e geometry(linestring, 3857)
);
create index joint_edge_set_k on joint_edge_set (k);

create table joint_merged_edges (
    synth_id   varchar(64),
    extent     geometry(linestring),
    station_id varchar(64) array[2],
    source_id  varchar(64) array
);
create index joint_merged_edges_source_id on joint_merged_edges using gin(source_id);


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

insert into redundant_joints (joint_id, line_id, station_id)
    select joint_id, array_agg(line_id), array_agg(distinct station_id) from (
        select n.station_id, e.line_id, unnest(e.station_id)
            from topology_nodes n
            join topology_edges e on e.line_id = any(n.line_id)
           where n.topology_name = 'joint'
    ) f (joint_id, line_id, station_id)
    where joint_id != station_id
    group by joint_id having count(distinct station_id) <= 2;

with redundant_joint_splits (station_id, line_id) as (
    select distinct array[least(joint_id, station_id[1]), greatest(joint_id, station_id[1])],
        array((select e.line_id from topology_edges e where e.line_id = any(j.line_id) and j.station_id[1] = any(e.station_id)))
        from redundant_joints j where array_length(j.station_id, 1) = 2 and array_length(j.line_id, 1) > 2

   union

   select distinct array[least(joint_id, station_id[2]), greatest(joint_id, station_id[2])],
       array((select e.line_id from topology_edges e where e.line_id = any(j.line_id) and j.station_id[2] = any(e.station_id)))
       from redundant_joints j where array_length(j.station_id, 1) = 2 and array_length(j.line_id, 1) > 2
) insert into redundant_splits (station_id, line_id)
   select station_id, line_id from redundant_joint_splits where array_length(line_id, 1) > 1;

with split_simplify_candidates (line_id, station_id, simple_extent, original_length, original_extents) as (
   select line_id, station_id, st_shortestline(a.area, b.area),
       (select avg(st_length(line_extent)) from topology_edges e where e.line_id = any(r.line_id)),
       (select st_multi(st_union(line_extent)) from topology_edges e where e.line_id = any(r.line_id))
       from redundant_splits r
       join power_station a on a.osm_id = station_id[1]
       join power_station b on b.osm_id = station_id[2]
) insert into simplified_splits (synth_id, station_id, source_id, simple_extent, original_extents, distortion)
     select concat('q', nextval('synthetic_objects')), station_id, line_id,
            simple_extent, original_extents,
            abs(original_length - st_length(simple_extent))
         from split_simplify_candidates
         where abs(original_length - st_length(simple_extent)) < 300;


insert into osm_objects (osm_id, objects)
       select synth_id, source_objects(source_id) from simplified_splits;

-- create new edges to replace the old ones
insert into topology_edges (line_id, station_id, line_extent, station_locations)
    select synth_id, station_id, simple_extent, array[a.location, b.location]
        from simplified_splits
        join power_station a on a.osm_id = station_id[1]
        join power_station b on b.osm_id = station_id[2];



-- replace edges in stations
insert into replaced_edges (station_id, old_id, new_id)
    select station_id, array_agg(distinct source_id), array_agg(distinct synth_id) from (
        select station_id[1], synth_id, unnest(source_id) from simplified_splits
        union
        select station_id[2], synth_id, unnest(source_id) from simplified_splits
    ) f (station_id, synth_id, source_id) group by station_id;

delete from topology_edges where line_id in (select unnest(old_id) from replaced_edges);

update topology_nodes n set line_id = array_replace(n.line_id, r.old_id, r.new_id)
       from replaced_edges r where n.station_id = r.station_id;

update redundant_joints j set line_id = array_replace(j.line_id, r.old_id, r.new_id)
       from replaced_edges r where j.joint_id = r.station_id;


-- create pairs out of simple joints
insert into joint_edge_pair (joint_id, left_id, right_id)
    select joint_id, least(line_id[1], line_id[2]), greatest(line_id[1], line_id[2])
        from redundant_joints
        where array_length(station_id, 1) = 2 and array_length(line_id, 1) = 2;

insert into joint_edge_set (k, v, e, s)
    select line_id, line_id, line_extent, station_id from topology_edges where line_id in (
        select unnest(line_id) from redundant_joints
    );

do $$
declare
    p joint_edge_pair;
    l joint_edge_set;
    r joint_edge_set;
begin
    for p in select * from joint_edge_pair loop
        select * into l from joint_edge_set where v = p.left_id;
        select * into r from joint_edge_set where v = p.right_id;
        if l.k != r.k then
            update joint_edge_set set k = l.k where k = r.k;
            update joint_edge_set
               set e = connect_lines(l.e, r.e),
                   s = array_sym_diff(l.s, r.s)
               where k = l.k;
        end if;
    end loop;
end;
$$ language plpgsql;

-- again replace edges
insert into joint_merged_edges (synth_id, extent, station_id, source_id)
    select concat('q', nextval('synthetic_objects')), e, s, g.v
       from joint_edge_set s join (
            select k, array_agg(v) from joint_edge_set group by k having count(*) > 1
       ) g(k,v) on s.v = g.k where array_length(s,1) is not null;

insert into osm_objects (osm_id, objects)
    select synth_id, source_objects(source_id) from joint_merged_edges;

insert into topology_edges (line_id, station_id, line_extent)
    select synth_id, station_id, extent from joint_merged_edges;

-- replace new edges
update topology_nodes n set line_id = array_replace(n.line_id, m.source_id, array[m.synth_id])
    from joint_merged_edges m where n.station_id = any(m.station_id);

-- remove dangling joints and internal joints
insert into removed_nodes (station_id)
    select joint_id from redundant_joints where array_length(station_id, 1) = 1
        union
     select joint_id from joint_edge_pair; -- all joints in joint_edge_pair are paired up by definition

insert into removed_edges (line_id)
    select distinct line_id from topology_edges e join removed_nodes n on n.station_id = any(e.station_id)
        union
    select distinct unnest(source_id) from simplified_splits
        union
    select distinct unnest(source_id) from joint_merged_edges;

-- remove nodes and edges, maybe make this a procedure?
update topology_nodes n set line_id = array_replace(n.line_id, r.line_id, array[]::varchar(64)[])
   from (
        select station_id, array_agg(e.line_id) from topology_nodes t
            join removed_edges e on e.line_id = any(t.line_id)
            group by station_id
   ) r(station_id, line_id) where r.station_id = n.station_id;

delete from topology_nodes where station_id in (select station_id from removed_nodes);
delete from topology_edges where line_id in (select line_id from removed_edges);

commit;
