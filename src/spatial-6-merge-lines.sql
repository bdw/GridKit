begin;
drop table if exists line_pairs;
drop table if exists line_sets;
drop table if exists merged_lines;
create table line_pairs (
    src text,
    dst text,
    primary key (src, dst)
);

create table line_sets (
    k text,
    v text,
    e geometry(linestring, 3857),
    t geometry(geometry, 3857),
    primary key (v)
);



create table merged_lines (
    synth_id  varchar(64),
    source_id varchar(64) array,
    extent    geometry(linestring, 3857),
    terminals geometry(geometry, 3857)
);


insert into line_pairs (src, dst)
    select distinct least(a.osm_id, b.osm_id), greatest(a.osm_id, b.osm_id)
        from terminal_intersections i
        join line_terminals a on a.id = i.src
        join line_terminals b on b.id = i.dst;

insert into line_sets (k, v, e, t)
    select osm_id, osm_id, extent, terminals from power_line where osm_id in (
        select src from line_pairs union select dst from line_pairs
    );


create index line_sets_k on line_sets (k);
create index line_sets_v on line_sets (v);
-- union-find algorithm again.

do $$
declare
    s line_sets;
    d line_sets;
    l line_pairs;
begin
    for l in select * from line_pairs loop
        select * into s from line_sets where v = l.src;
        select * into d from line_sets where v = l.dst;
        if s.k != d.k then
            update line_sets set k = s.k where k = d.k;
            update line_sets set e = connect_lines(s.e, d.e),
                                 t = connect_lines_terminals(s.t, d.t)
                where k = s.k;
        end if;
     end loop;
end
$$ language plpgsql;


insert into merged_lines (synth_id, extent, terminals, source_id)
    select concat('m', nextval('synthetic_objects')), s.e, s.t, array_agg(v)
       from line_sets s join power_line l on s.v = l.osm_id
       group by s.k, s.e, s.t having count(*) >= 2;

insert into power_line (osm_id, power_name, extent, terminals)
    select synth_id, 'merge', extent, terminals from merged_lines;

insert into osm_objects (osm_id, objects)
    select synth_id, source_objects(source_id) from merged_lines;

delete from power_line where osm_id in (select unnest(source_id) from merged_lines);
commit;
