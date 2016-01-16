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
        i terminal_intersections;
        s int;
        d int;
begin
        for i in select src, dst from terminal_intersections loop
            s := (select k from terminal_union_sets where v = i.src);
            d := (select k from terminal_union_sets where v = i.dst);
            if s != d then
                update terminal_union_sets set k = s where k = d;
            end if;
        end loop;
end
$$ language plpgsql;

commit;
