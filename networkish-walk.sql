drop table if exists networkish;
create table networkish (
	src integer,
	dst integer
);

insert into networkish (src, dst) values (1,2), (2,3), (3,6), (4,5), (5,6);
with recursive paths (src, dst, path) as (
	select src, dst, array[src, dst] as path from networkish
	union
	select a.src, b.dst, a.path || b.dst as path from paths a
		join networkish b on b.src = a.dst
) select * from paths a /* where not exists (
	select * from paths b where b.path @> a.path and a.path != b.path
) */;