begin;
drop function if exists jsonb_first_key(v jsonb);

create function jsonb_first_key(v jsonb) returns text as $$
begin
     return k from (select jsonb_object_keys(v)) t(k) limit 1;
end;
$$ language plpgsql;


commit;
