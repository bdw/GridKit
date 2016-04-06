begin;
/*
drop table if exists line_osm_names;
create table line_osm_names (
    osm_name varchar(64) primary key
);

insert into line_osm_names (osm_name)
   select osm_name from osm_ids where power_type = 'l';
*/
-- deal with 'divisible' complex lines first
update electric_tags e
   set cables = array_fill(cables[1]/array_length(voltage,1),
                           array[array_length(voltage,1)])
   from line_osm_names l
   where l.osm_name = e.osm_name
     and array_length(voltage,1) > 1 and array_length(cables, 1) = 1
     and ((cables[1] / array_length(voltage, 1)) % 3) = 0;

update electric_tags e
   set cables = array_fill(cables[1]/array_length(frequency,1),
                           array[array_length(frequency,1)])
   from line_osm_names l
   where l.osm_name = e.osm_name
     and array_length(frequency,1) > 1 and array_length(cables, 1) = 1
     and ((cables[1] / array_length(frequency, 1)) % 3) = 0;

-- fix 16.67 Hz to 16.7 frequency for consistency. 
update electric_tags e
   set frequency = array_replace(frequency::numeric[],16.67,16.7)
   where 16.67 = any(frequency);

-- otherwise, not much to do now, so far as I know

commit;
