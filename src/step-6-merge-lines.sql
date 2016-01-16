begin;
drop table if exists line_pairs;
drop table if exists line_sets;
create table line_pairs (
    src text,
    dst text,
    primary key (src, dst)
);

create table line_sets (
    k text,
    v text,
    e geometry(linestring, 3857),
    primary key (v)
);

insert into line_pairs (src, dst)
   select distinct least(a.osm_id, b.osm_id), greatest(a.osm_id, b.osm_id)
       from terminal_intersections i
       join line_terminals a on a.id = i.src
       join line_terminals b on b.id = i.dst;

insert into line_sets (k, v, e) select osm_id, osm_id, extent from power_line;


create index line_sets_k on line_sets (k);
create index line_sets_v on line_sets (v);
-- union-find algorithm again.

do $$
declare
    s record;
    d record;
    l line_pairs;
begin
    for l in select * from line_pairs loop
        select k, e into s from line_sets where v = l.src;
        select k, e into d from line_sets where v = l.dst;
        if s.k != d.k then
            update line_sets set k = s.k where k = d.k;
            -- hang on, not this simple
            update line_sets set e = st_makeline(s.e, d.e) where k = s.k;
        end if;
     end loop;
end
$$ language plpgsql;

drop table if exists merged_lines;
create table merged_lines (
       synth_id varchar(64),
       extent   geometry(linestring, 3857),
       source text[],
       objects  text[]
);
insert into merged_lines (synth_id, extent, source, objects)
       select concat('m', nextval('synthetic_objects')), s.e,
              array_agg(v), array_agg(distinct (select unnest(l.objects)))
              from line_sets s join power_line l on s.v = l.osm_id
              group by s.k, s.e having count(*) >= 2;
commit;
