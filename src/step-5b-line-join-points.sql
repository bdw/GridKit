drop index if exists terminal_intersection_join;
create index terminal_intersection_join on terminal_intersections (src, dst);

with recursive terminal_intersection_union (v) as (
	select array[src,dst] as v from terminal_intersections
	union all
	select u.v || i.dst from terminal_intersections i, terminal_intersection_union u
		where i.src = any(u.v) and not i.dst = any(u.v)
) select v from terminal_intersection_union where array_length(v,1) > 2 limit 5000;
