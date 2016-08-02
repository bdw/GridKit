begin;
drop table if exists station_structure;
drop table if exists station_terminals;
drop table if exists merged_station_tags;

create table station_structure (
    station_id integer primary key,
    voltage integer array,
    frequency float array,
    station_name text,
    station_operator text,
    substation text
);

create table station_terminals (
   station_id integer primary key,
   voltage integer array,
   frequency float array
);

create table merged_station_tags (
   like station_tags
);


-- step one, the set of connected lines
insert into station_terminals (station_id, voltage, frequency)
     select n.station_id,
            array_agg(distinct l.voltage) filter (where l.voltage is not null),
            array_agg(distinct l.frequency) filter (where l.frequency is not null)
       from topology_nodes n
       join line_structure l on l.line_id = any(n.line_id)
      group by n.station_id;

-- step two, merge station tags
insert into merged_station_tags (station_id, power_name, voltage, frequency, station_name, station_operator, substation)
     select derived_id,
            array_to_string(array(select distinct power_name from station_tags where station_id = any(source_id)), ';'),
            array(select distinct unnest(voltage) from station_tags where station_id = any(source_id)),
            array(select distinct unnest(frequency) from station_tags where station_id = any(source_id)),
            array_to_string(array(select distinct station_name from station_tags where station_id = any(source_id)), ';'),
            array_to_string(array(select distinct station_operator from station_tags where station_id = any(source_id)), ';'),
            array_to_string(array(select distinct substation from station_tags where station_id = any(source_id)), ';')
       from derived_objects
      where derived_type = 's' and operation = 'merge' and source_type = 's'
        and exists (select 1 from topology_nodes where station_id = derived_id);
 
-- step three, merge connected-line information with tag information
insert into station_structure (station_id, voltage, frequency, station_name, station_operator, substation)
    select t.station_id,
           array(select unnest(t.voltage) union select unnest(s.voltage)),
           array(select unnest(t.frequency) union select unnest(s.frequency)), station_name, station_operator, substation
      from station_tags t
      join station_terminals s on s.station_id = t.station_id;

insert into station_structure (station_id, voltage, frequency, station_name, station_operator, substation)
    select t.station_id,
           array(select unnest(t.voltage) union select unnest(s.voltage)),
           array(select unnest(t.frequency) union select unnest(s.frequency)), station_name, station_operator, substation
      from merged_station_tags t
      join station_terminals s on s.station_id = t.station_id;

commit;
