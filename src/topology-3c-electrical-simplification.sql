begin;
drop table if exists composite_lines;

create table composite_lines (
    line_id integer primary key,
    num_objects integer,
    old_voltage integer array,
    old_frequency float array,
    old_cables integer array,
    old_wires integer array,
    new_voltage integer array,
    new_frequency float array,
    new_cables integer array,
    new_wires integer array
);

create table striped_lines (
    line_id integer,
    voltage integer,
    frequency float,
    num_objects integer,
    occurence integer,
    old_cables integer array,
    new_cables integer,
    old_wires integer array,
    new_wires integer
);

-- TODO

-- the 'proper' way to deal with this, is to construct operation trees
-- for the construction of each composite line, and then to merge the
-- properties according to this structure. However, properties are
-- often wrong, so it is not directly obvious how to merge conflicting
-- values.

-- first handle the simple cases, zero voltage is just nonsense
update electrical_properties set voltage = array_remove(voltage, array[0])
       where 0 = any(voltage);

update electrical_properties set voltage = array[voltage[1]]
       where array_length(voltage,1) > 1 and voltage[1] = all(voltage);

update electrical_properties set frequency = array[frequency[1]]
       where array_length(frequency,1) > 1 and frequency[1] = all(frequency);

-- todo, detect lateral merges to sum cables... failure to do so will
-- result in underestimation of line cables / wires

update electrical_properties set cables = array[cables[1]]
       where array_length(cables,1) > 1 and cables[1] = all(cables);

update electrical_properties set wires = array[wires[1]]
       where array_length(wires,1) > 1 and wires[1] = all(wires);

-- insert missing values?
update electrical_properties set frequency = array[50.0]
    where array_length(frequency, 1) is null;

update electrical_properties set cables = array[3]
    where array_length(cables, 1) is null;

update electrical_properties e set wires = array[r.wires]
   from reference_parameters r
   where array_length(e.wires, 1) is null
     and array_length(e.voltage, 1) = 1
     and e.voltage[1] = r.voltage;

update electrical_properties set wires = array[1]
    where array_length(wires, 1) is null;

-- any conflicting wires / numbers for single frequency / voltage
-- levels can't be interpreted correctly, so choose the most common
update electrical_properties set cables = array[array_most_common(cables)]
    where array_length(voltage,1) = 1
      and array_length(frequency, 1) = 1
      and array_length(cables, 1) > 1;

update electrical_properties set wires = array[array_most_common(wires)]
    where array_length(voltage, 1) = 1
      and array_length(frequency, 1) = 1
      and array_length(wires, 1) > 1;

insert into composite_lines (line_id, num_objects, old_voltage, old_frequency, old_cables, old_wires)
    select e.power_id, array_length(objects, 1), voltage, frequency, cables, wires
       from electrical_properties e
       join osm_objects o on o.power_id = e.power_id and o.power_type = e.power_type
       where e.power_type = 'l' and array_length(voltage, 1) > 1 or array_length(frequency, 1) > 1;

-- insert cleverness here....

-- detect striped lines (hang on, this is not correct...)
insert into striped_lines (line_id, voltage, frequency, old_cables, old_wires, num_objects, occurence)
     select line_id,  voltage, frequency, array_agg(cables), array_agg(wires), num_objects, count(*)
         from (
              select line_id, unnest(old_voltage), unnest(old_frequency), unnest(old_cables), unnest(old_wires), num_objects
                  from composite_lines
                  where (array_length(old_voltage, 1) = array_length(old_frequency, 1) or array_length(old_frequency, 1) = 1)
                    and (array_length(old_voltage, 1) = array_length(old_cables, 1) or array_length(old_cables, 1) = 1)
                    and (array_length(old_voltage, 1) = array_length(old_wires, 1) or array_length(old_wires, 1) = 1)
         ) t (line_id, voltage, frequency, cables, wires, num_objects)
         group by line_id, voltage, frequency, num_objects;

commit;
