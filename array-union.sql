drop table if exists foobar;
create table foobar (
       foo int[]
);

insert into foobar (foo) values (array[1,2,3]), (array[3,4,5]), (array[5,11]), (array[6,7,8]), (array[8,9,10]);
with recursive foo_start(foo, bar) as (
       select foo, (select min(e) from (select unnest(foo) as e) as m) as bar from foobar
), combinations as (
       select * from foo_start
       union
       select array_agg(distinct e order by e) as foo, bar from (
              select unnest(a.foo || b.foo) as e, least(a.bar, b.bar) as bar
                     from combinations a
                     join foo_start b on b.foo && a.foo
       ) z group by bar
) select * from combinations a where not exists (
       select * from combinations b where b.foo @> a.foo and b.foo != a.foo
);
