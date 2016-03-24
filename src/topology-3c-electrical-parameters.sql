begin;
-- take a look to what we're up against.
select v, f, c, w, count(*) from (
    select array_length(voltage,1), array_length(frequency, 1),
       array_length(conductor_bundles, 1), array_length(subconductors, 1)
       from electrical_properties where power_type = 'l' and voltage is not null
) t (v,f,c,w) group by v,f,c,w order by count(*) desc;

-- or this
select v, count(*) from (
    select unnest(voltage) from electrical_properties where power_type = 'l'
) t(v) group by v order by v desc;

commit;
