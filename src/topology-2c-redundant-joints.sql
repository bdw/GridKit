begin;
drop table if exists redundant_joints;
drop table if exists joint_edge_pair;
drop table if exists joint_edge_set;
drop table if exists joint_merged_edges;

create table redundant_joints (
    joint_id   varchar(64),
    line_id    varchar(64) array,
    station_id varchar(64) array,
    primary key (joint_id)
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

insert into redundant_joints (joint_id, line_id, station_id)
    select joint_id, array_agg(line_id), array_agg(distinct station_id) from (
        select n.station_id, e.line_id, unnest(e.station_id)
            from topology_nodes n
            join topology_edges e on e.line_id = any(n.line_id)
           where n.topology_name = 'joint'
    ) f (joint_id, line_id, station_id)
    where joint_id != station_id
    group by joint_id having count(distinct station_id) <= 2;



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

insert into joint_merged_edges (synth_id, extent, station_id, source_id)
    select concat('q', nextval('synthetic_objects')), e, s, g.v
       from joint_edge_set s join (
            select k, array_agg(v) from joint_edge_set group by k having count(*) > 1
       ) g(k,v) on s.v = g.k where array_length(s,1) is not null;


insert into osm_objects (osm_id, objects)
    select synth_id, source_objects(source_id) from joint_merged_edges;

insert into topology_edges (line_id, station_id, line_extent, station_locations)
    select synth_id, e.station_id, extent, array[a.station_location, b.station_location]
           from joint_merged_edges e
           join topology_nodes a on a.station_id = e.station_id[1]
           join topology_nodes b on b.station_id = e.station_id[2];

delete from topology_nodes where station_id in (select joint_id from joint_edge_pair);
delete from topology_edges where line_id in (select unnest(source_id) from joint_merged_edges);

-- end point updates
update topology_nodes n set line_id = array_replace(n.line_id, m.source_id, array[m.synth_id])
    from joint_merged_edges m where n.station_id = any(m.station_id);


commit;
