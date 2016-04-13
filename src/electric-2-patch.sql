begin;

drop function if exists fair_division(n int, d int);
drop function if exists array_mult(n int array, x int);
create function fair_division (n int, d int) returns int array as $$
begin
    return array_cat(array_fill( n / d + 1, array[n % d]), array_fill( n / d, array[d - n % d]));
end;
$$ language plpgsql;

create function array_mult(n int array, x int) returns int array as $$
begin
    return array(select v*x from unnest(n) v);
end;
$$ language plpgsql;


drop table if exists divisible_cables;
create table divisible_cables (
    osm_name varchar(64) primary key,
    num_lines integer,
    total_cables integer,
    cables integer array
);

insert into divisible_cables (osm_name, num_lines, total_cables)
    select osm_name, case when array_length(voltage, 1) > 1 then array_length(voltage, 1)
                          else array_length(frequency, 1) end, cables[1]
        from electric_tags e
        where exists (select 1 from power_type_names t where t.power_name = e.power_name and t.power_type = 'l')
          and (array_length(voltage, 1) > 1 or array_length(frequency, 1) > 1) and array_length(cables, 1) = 1
          and cables[1] > 4;


update divisible_cables
     set cables = case when total_cables >= num_lines * 3 and total_cables % 3 = 0 then array_mult(fair_division(total_cables / 3, num_lines), 3)
                       when total_cables >= num_lines * 4 and total_cables % 4 = 0 then array_mult(fair_division(total_cables / 4, num_lines), 4)
                       when total_cables >= 7 and (total_cables - 4) % 3 = 0 then array_cat(array[4],  array_mult(fair_division((total_cables - 4) / 3, num_lines - 1), 3))
                       when total_cables >= 11 and (total_cables - 8) % 3 = 0 then array_cat(array[8], array_mult(fair_division((total_cables - 8) / 3, num_lines-1), 3))
                       else array[total_cables] end;

-- can't seem to solve this one analytically...
update divisible_cables set cables = array[4,4,3] where total_cables = 11 and num_lines = 3;

update electric_tags e set cables = d.cables from divisible_cables d where d.osm_name = e.osm_name;

-- fix 16.67 Hz to 16.7 frequency for consistency.
update electric_tags e
   set frequency = array_replace(frequency::numeric[],16.67,16.7)
   where 16.67 = any(frequency);

-- fix inconsistently striped lines

drop table if exists inconsistent_line_tags;
create table inconsistent_line_tags (
    osm_name varchar(64) primary key,
    voltage integer array,
    frequency float array,
    cables integer array,
    wires integer array
);

-- this affects surprisingly few lines, actually
insert into inconsistent_line_tags (osm_name, voltage, frequency, cables, wires)
   select osm_name, voltage, frequency, cables, wires from electric_tags e
       where exists (select 1 from power_type_names t where t.power_name = e.power_name and t.power_type = 'l')
        and (array_length(voltage, 1) >= 3
             and (array_length(frequency, 1) > 1 and array_length(frequency, 1) < array_length(voltage, 1) or
                  array_length(cables, 1) > 1 and array_length(cables, 1) < array_length(voltage, 1) or
                  array_length(wires, 1) > 1 and array_length(wires, 1) < array_length(voltage, 1))

          or array_length(frequency, 1) >= 3
             and (array_length(voltage, 1) > 1 and array_length(voltage, 1) < array_length(frequency, 1) or
                  array_length(cables, 1) > 1 and array_length(cables, 1) < array_length(frequency, 1) or
                  array_length(wires, 1) > 1 and array_length(wires, 1) < array_length(frequency, 1))

          or array_length(cables, 1) >= 3
             and (array_length(voltage, 1) > 1 and array_length(voltage, 1) < array_length(cables, 1) or
                  array_length(frequency, 1) > 1 and array_length(frequency, 1) < array_length(cables, 1) or
                  array_length(wires, 1) > 1 and array_length(wires, 1) < array_length(cables, 1))

          or array_length(wires, 1) >= 3
             and (array_length(voltage, 1) > 1 and array_length(voltage, 1) < array_length(wires, 1) or
                  array_length(frequency, 1) > 1 and array_length(frequency, 1) < array_length(wires, 1) or
                  array_length(cables, 1) > 1 and array_length(cables, 1) < array_length(wires, 1)));

-- TODO patch it up


commit;
