-- assign tags to stations missing them
begin;
drop function if exists merge_power_tags(a hstore array);
drop table if exists derived_tags;

create function merge_power_tags (a hstore array) returns hstore as $$
declare
    r hstore;
    t hstore;
    k text;
    v text;
begin
    r = hstore('_merged', case when array_length(a, 1) > 1 then 'yes' else 'no' end);
    for t in select unnest(a) loop
        for k in select skeys(t) loop
            if not r ? k then
                r = r || hstore(k, t->k);
            elsif (r->k) != (t->k) and k in ('voltage', 'wires', 'cables', 'frequency', 'name') then
                -- assume we can't fix this now, so join them separated by semicolons
                v = (r->k) || ';' || (t->k);
                r = r || hstore(k, v);
            end if;
        end loop;
    end loop;
    return r;
end
$$ language plpgsql;


-- assign tags for all newly created objects
create table derived_tags (
    osm_id varchar(64) primary key,
    tags   hstore
);

insert into derived_tags (osm_id, tags)
    select o.osm_id, merge_power_tags(array_agg(t.tags))
        from osm_objects o
        join osm_tags t on t.osm_id = any(o.objects)
                       and o.osm_id != t.osm_id
        where exists (
            select line_id from topology_edges where o.osm_id = line_id
            union all
            select station_id from topology_nodes where o.osm_id = station_id
        )
        group by o.osm_id;

insert into osm_tags (osm_id, tags)
    select osm_id, tags from derived_tags d
       where not exists (select * from osm_tags t where t.osm_id = d.osm_id);

update osm_tags t set tags = d.tags
    from derived_tags d where d.osm_id = t.osm_id;



-- do a check. after topology-3a this should not be possible because all mapped objects
-- have at least a 'power' tag, so they should exist
do $$
declare
    missing_node_tags integer;
    missing_edge_tags integer;
begin
    missing_node_tags = count(*) from topology_nodes where not exists (
         select * from osm_tags where osm_id = station_id
    );
    missing_edge_tags = count(*) from topology_edges where not exists (
        select * from osm_tags where osm_id = line_id
    );
    if missing_node_tags > 0
    then
        raise exception 'nodes without tags';
    elsif missing_edge_tags > 0
    then
        raise exception 'stations without tags';
    else
        raise notice 'Assigned tags to all lines and stations';
     end if;
end;
$$ language plpgsql;

commit;
