drop function if exists setmerge(a anyarray, b anyelement);
create function setmerge(a anyarray, b anyelement) returns anyarray
as
$$
begin
	return (select array_agg(distinct e order by e) from (
		select unnest(a || b) as e
	) f);
end
$$
language plpgsql;

select setmerge(array[1,2,3],array[3,4]), setmerge(array[1,2,3], 5);
