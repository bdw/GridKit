begin;
-- deal with 'divisible' complex lines first
update electric_tags e
   set cables = array_fill(cables[1]/array_length(voltage,1),
                           array[array_length(voltage,1)])
   where exists (select 1 from power_type_names t where t.power_name = e.power_name and t.power_type = 'l')
     and array_length(voltage,1) > 1 and array_length(cables, 1) = 1
     and ((cables[1] / array_length(voltage, 1)) % 3) = 0;

update electric_tags e
   set cables = array_fill(cables[1]/array_length(frequency,1),
                           array[array_length(frequency,1)])
   where exists (select 1 from power_type_names t where t.power_name = e.power_name and t.power_type = 'l')
     and array_length(frequency,1) > 1 and array_length(cables, 1) = 1
     and ((cables[1] / array_length(frequency, 1)) % 3) = 0;

-- fix 16.67 Hz to 16.7 frequency for consistency. 
update electric_tags e
   set frequency = array_replace(frequency::numeric[],16.67,16.7)
   where 16.67 = any(frequency);

-- TODO fix inconsistently striped tags

commit;
