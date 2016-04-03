begin;
drop table if exists line_pairs;
drop table if exists line_sets;
drop table if exists merged_lines;

create table line_pairs (
    src integer,
    dst integer,
    primary key (src, dst)
);

create table line_sets (
    k integer not null,
    v integer primary key,
    e geometry(linestring, 3857),
    t geometry(geometry, 3857)
);


create table merged_lines (
    new_id    integer primary key,
    old_id    integer array,
    extent    geometry(linestring, 3857),
    terminals geometry(geometry, 3857)
);


insert into line_pairs (src, dst)
    select distinct least(a.line_id, b.line_id), greatest(a.line_id, b.line_id)
        from terminal_intersections i
        join line_terminals a on a.terminal_id = i.src
        join line_terminals b on b.terminal_id = i.dst
        where not exists (
            select 1 from line_joints j
                where a.terminal_id = any(j.terminal_id)
                   or b.terminal_id = any(j.terminal_id)
        );

insert into line_sets (k, v, e, t)
    select line_id, line_id, extent, terminals from power_line
    where line_id in (
        select src from line_pairs union select dst from line_pairs
    );


create index line_sets_k on line_sets (k);
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


insert into merged_lines (new_id, extent, terminals, old_id)
    select nextval('line_id'), s.e, s.t, array_agg(v)
       from line_sets s join power_line l on s.v = l.line_id
       group by s.k, s.e, s.t having count(*) >= 2;

insert into power_line (line_id, power_name, extent, terminals)
    select new_id, 'merge', extent, terminals from merged_lines;

insert into osm_objects (power_id, power_type, objects)
    select new_id, 'l', track_objects(old_id, 'l', 'join') from merged_lines;

delete from power_line l where exists (
    select 1 from merged_lines m where m.new_id = l.line_id
);
commit;
