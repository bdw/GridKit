drop table if exists foobar;
drop function if exists addset(v int[], a int);
/* our vertices table */
create table foobar (
       src int,
       dst int
);

/* Create a small function to treat an array like a set */
create function addset(v int[], a int) returns int[]
as $$
begin
	return (select array_agg(e order by e) from (select unnest(v || a) as e) f);
end
$$ language plpgsql;
/* fill our table with vertices, note the ordering of each value */
insert into foobar (src, dst) values (1,2), (1,3), (2,3), (3,4), (4,5), (6,7), (6,8);
/* use a recursive query to extend the sets */
with recursive foo_union (v) as (
	select array[src, dst] as v from foobar
	union all
	/* join self to original array; i can use a CTE as a 'starter', but that is not necessary here */
	select addset(v, dst) from foo_union u, foobar f
		where src = any(v) and not dst = any(v)
) select distinct v from foo_union a where not exists (
	/* eliminate the many overlapping results */
	select * from foo_union b where b.v @> a.v and b.v != a.v
);