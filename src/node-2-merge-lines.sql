begin;
drop table if exists node_line_pair;
drop table if exists node_line_set;
drop table if exists node_merged_lines;

create table node_line_pair (
    src bigint not null,
    dst bigint not null
);

-- todo, find a way to abstract beyond this
create table node_line_set (
    v bigint,
    k bigint not null,
    e geometry(linestring, 3857),
    primary key (v)
);

create table node_merged_lines (
    line_id integer not null,
    way_id  bigint array,
    extent  geometry(linestring, 3857)
);

create index node_line_set_k on node_line_set (k);

insert into node_line_pair (src, dst)
    select way_id[1], way_id[2] from shared_nodes
        where 'l' = all(power_type)
        and array_length(way_id, 1) = 2
        and path_idx[1] in (0, 1) and path_idx[2] in (0,1);

insert into node_line_set (v, k, e)
    select way_id, way_id, line from way_geometry
        where way_id in (select src from node_line_pair union all select dst from node_line_pair);

do $$
declare
    p node_line_pair;
    s node_line_set;
    d node_line_set;
    e geometry(linestring);
begin
    for p in select * from node_line_pair
    loop
        select * into s from node_line_set where v = p.src;
        select * into d from node_line_set where v = p.dst;
        if s.k != d.k
        then
            update node_line_set set k = s.k where k = d.k;
            update node_line_set set e = connect_lines(s.e, d.e) where k = s.k;
        end if;
    end loop;
end
$$ language plpgsql;

insert into node_merged_lines (line_id, way_id, extent)
    select nextval('line_id'), array_agg(v), e
        from node_line_set group by k, e;


insert into power_line (line_id, power_name, extent, terminals)
    select line_id, 'merged', extent, buffered_terminals(extent)
        from node_merged_lines;

insert into osm_objects (power_id, power_type, objects)
    select line_id, 'l', array(
        select osm_name from osm_ids i where i.osm_id = any(m.way_id) and i.osm_type = 'w'
    )
    from node_merged_lines m;

delete from power_line l where exists (
    select 1 from osm_ids
        where osm_type = 'w' and osm_id in (
            select src from node_line_pair union select dst from node_line_pair
        )
        and power_type = 'l' and power_id = line_id
);

commit;
