drop function if exists setmerge(a int[], b int[]);
drop function if exists setadd(int[], int);
create function setmerge(a int[], b int[]) returns int[]
as
$$
begin
	return (select array_agg(distinct e order by e) from (
		select unnest(a || b) as e
	) f);
end
$$
language plpgsql;
create function setadd(s int[], v int) returns int[]
as
$$
begin
        return (select array_agg(distinct e order by e) from (
               select unnest(s || v) as e
        ) f);
end
$$
language plpgsql;




select setmerge(array[1,2,3],array[3,4]);
