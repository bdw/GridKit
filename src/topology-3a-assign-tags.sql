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
    power_id   integer,
    power_type char(1),
    tags       hstore,
    primary key (power_id, power_type)
);

insert into derived_tags (power_id, power_type, tags)
    select o.power_id, o.power_type, merge_power_tags(array_agg(t.tags))
        from osm_objects o
        join osm_ids i on i.osm_name = any(o.objects)
        join osm_tags t on
                   t.power_id = i.power_id and t.power_type = i.power_type
          and not (o.power_id = t.power_id and o.power_type = t.power_type)
        where exists (
            select 1 from topology_edges where o.power_id = line_id and o.power_type = 'l'
            union all
            select 1 from topology_nodes where o.power_id = station_id and o.power_type = 's'
        )
        group by o.power_id, o.power_type;

insert into osm_tags (power_id, power_type, tags)
    select power_id, power_type, tags from derived_tags d
        where not exists (
            select 1 from osm_tags t where t.power_id = d.power_id and t.power_type = d.power_type
        );

/*
update osm_tags t set tags = d.tags
    from derived_tags d
    where d.power_id = t.power_id
      and d.power_type = t.power_type;
*/

-- do a check. after topology-3a this should not be possible because all mapped objects
-- have at least a 'power' tag, so they should exist
do $$
declare
    missing_node_tags integer;
    missing_edge_tags integer;
begin
    missing_node_tags = count(*) from topology_nodes where not exists (
         select 1 from osm_tags where power_id = station_id and power_type = 's'
    );
    missing_edge_tags = count(*) from topology_edges where not exists (
        select 1 from osm_tags where power_id = line_id and power_type = 'l'
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
