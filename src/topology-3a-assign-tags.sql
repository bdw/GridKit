-- assign tags to stations missing them
begin;
drop table if exists osm_tags;
drop table if exists merged_tags;
create table osm_tags (
    osm_id varchar(64),
    tags   hstore,
    primary key (osm_id)
);
create table merged_tags (
    osm_id varchar(64),
    tags   hstore,
    primary key (osm_id)
);


drop function if exists setmerge(a anyarray, b anyelement);
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


drop function if exists merge_power_tags(a hstore array);

create function merge_power_tags (a hstore array) returns hstore as $$
declare
    r hstore;
    t hstore;
    k text;
    v text;
begin
    r = hstore('_merged', 'yes');
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
    select concat('n', id), hstore(tags) from planet_osm_nodes;
insert into osm_tags (osm_id, tags)
    select concat('w', id), hstore(tags) from planet_osm_ways;

update power_line l set tags = t.tags
    from osm_tags t
    where l.tags is null and array_length(l.objects, 1) = 1
        and t.osm_id = l.objects[1];

insert into merged_tags (osm_id, tags)
    select l.osm_id, merge_power_tags(array_agg(t.tags))
        from power_line l join osm_tags t on t.osm_id = any(l.objects)
        where l.tags is null group by l.osm_id;

insert into merged_tags (osm_id, tags)
    select s.osm_id, merge_power_tags(array_agg(t.tags))
        from power_station s join osm_tags t on t.osm_id = any(s.objects)
        where s.tags is null group by s.osm_id;

update power_line l set tags = m.tags
       from merged_tags m where l.tags is null and m.osm_id = l.osm_id;

update power_station s set tags = m.tags
       from merged_tags m where s.tags is null and m.osm_id = s.osm_id;

commit;
