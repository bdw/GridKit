begin;
drop table if exists composite_lines;

create table composite_lines (
    line_id integer primary key,
    num_objects integer,
    voltage integer array,
    frequency float array,
    old_cables integer array,
    new_cables integer array
);


-- first handle the simple cases
update electrical_properties set voltage = array_remove(voltage, array[0])
       where 0 = any(voltage);

update electrical_properties set voltage = array[voltage[1]]
       where array_length(voltage,1) > 1 and voltage[1] = all(voltage);

update electrical_properties set frequency = array[frequency[1]]
       where array_length(frequency,1) > 1 and frequency[1] = all(frequency);

update electrical_properties set cables = array[cables[1]]
       where array_length(cables,1) > 1 and cables[1] = all(cables);

update electrical_properties set wires = array[wires[1]]
       where array_length(wires,1) > 1 and wires[1] = all(wires);

-- any conflicting wires / numbers for single frequency / voltage
-- levels can't be interpreted correctly, so choose the most common

update electrical_properties set cables = array[array_most_common(cables)]
       where array_length(voltage,1) = 1 and array_length(cables, 1) > 1 and
       (array_length(frequency, 1) = 1 or array_length(frequency, 1) is null);

update electrical_properties set wires = array[array_most_common(wires)]
       where array_length(voltage, 1) = 1 and array_length(wires, 1) > 1 and
       (array_length(frequency, 1) = 1 or array_length(frequency, 1) is null);

-- however, in some cases, voltage levels are composite, meaning a
-- line really carries more than one voltage or frequency, and in this case we have
-- to cleverly divide cables
insert into composite_lines (line_id, num_objects, voltage, frequency, old_cables)
    select e.power_id, array_length(objects, 1), voltage, frequency, cables
       from electrical_properties e
       join osm_objects o on o.power_id = e.power_id and o.power_type = e.power_type
       where e.power_type = 'l'
             and array_length(objects, 1) < (array_length(voltage, 1) * array_length(frequency, 1));


commit;
