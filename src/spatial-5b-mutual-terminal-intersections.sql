begin;
drop table if exists terminal_sets;
create table terminal_sets (
    v int primary key,
    k int not null
);
create index terminal_sets_k on terminal_sets (k);
insert into terminal_sets (k, v)
    select id, id from line_terminals;

do $$
declare
    i record;
    s int;
    d int;
begin
    for i in select src, dst from terminal_intersections loop
        s := (select k from terminal_sets where v = i.src);
        d := (select k from terminal_sets where v = i.dst);
        if s != d then
            update terminal_sets set k = s where k = d;
        end if;
    end loop;
end
$$ language plpgsql;
--  select k, array_agg(v) from terminal_sets group by k having count(*) > 1 limit 100;
commit;
