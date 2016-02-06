-- assign tags to stations missing them
begin;
drop function if exists setmerge(a anyarray, b anyelement);
drop function if exists merge_power_tags(a hstore array);




create function setmerge(a anyarray, b anyelement) returns anyarray
as
$$
begin
    return array_agg(distinct e order by e) from (
        select unnest(a || b) as e
    ) f;
end
$$
language plpgsql;


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
            elsif (r->k) != (t->k) and k in ('voltage', 'wires', 'cables', 'frequency') then
                -- assume we can't fix this now, so join them separated by semicolons
                v = array_to_string(setmerge(string_to_array(r->k, ';'), t->k), ';');
                r = r || hstore(k, v);
            end if;
        end loop;
    end loop;
    return r;
end
$$ language plpgsql;


insert into osm_tags (osm_id, tags)
    select l.osm_id, merge_power_tags(array_agg(t.tags))
       from power_line l
       join osm_objects o on l.osm_id = o.osm_id
       join osm_tags t on t.osm_id = any(o.objects)
       where l.osm_id not in (select osm_id from osm_tags)
       group by l.osm_id;

insert into osm_tags (osm_id, tags)
    select s.osm_id, merge_power_tags(array_agg(t.tags))
       from power_station s
       join osm_objects o on s.osm_id = o.osm_id
       join osm_tags t on t.osm_id = any(o.objects)
       where s.osm_id not in (select osm_id from osm_tags)
       group by s.osm_id;



commit;
