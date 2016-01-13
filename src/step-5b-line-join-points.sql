begin;
drop table if exists terminal_union_sets;
create table terminal_union_sets (
       k int,
       v int
);
create index tusets_k on terminal_union_sets (k);
create index tusets_v on terminal_union_sets (v);
insert into terminal_union_sets (k, v)
       select id, id from line_terminals;
do $$
declare
        r record;
        ksrc int;
        kdst int;
begin
        for r in select src, dst from terminal_intersections loop
            ksrc := (select k from terminal_union_sets where v = r.src);
            kdst := (select k from terminal_union_sets where v = r.dst);
            if ksrc != kdst then
                update terminal_union_sets set k = ksrc where k = kdst;
            end if;
        end loop;
end
$$ language plpgsql;

commit;
