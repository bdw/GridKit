begin;
drop table if exists terminal_sets;
create table terminal_sets (
    v integer primary key,
    k integer not null
);
create index terminal_sets_k on terminal_sets (k);

insert into terminal_sets (k, v)
    select src, src from terminal_intersections
        union
    select dst, dst from terminal_intersections;

do $$
declare
    i terminal_intersections;
    s int;
    d int;
begin
    for i in select * from terminal_intersections loop
        s := (select k from terminal_sets where v = i.src);
        d := (select k from terminal_sets where v = i.dst);
        if s != d then
            update terminal_sets set k = s where k = d;
        end if;
    end loop;
end
$$ language plpgsql;

commit;
