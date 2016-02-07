begin;

drop function if exists string_to_integer_array(a text, b text);
drop function if exists string_to_float_array(a text, b text);
drop function if exists number_of_wires(a text);
drop table if exists wires_to_numbers;

create function string_to_integer_array(a text, b text) returns integer array as $$
declare
    r integer array;
    t text;
begin
    for t in select unnest(string_to_array(a, b)) loop
        begin
            r = r || t::int;
        exception when others then
            r = r || null;
        end;
    end loop;
    return r;
end;
$$ language plpgsql;

create function string_to_float_array(a text, b text) returns float array as $$
declare
    r float array;
    t text;
begin
    for t in select unnest(string_to_array(a, b)) loop
        begin
            r = r || t::float;
        exception when others then
            r = r || null;
        end;
    end loop;
    return r;
end;
$$ language plpgsql;


create table wires_to_numbers (
    name varchar(16),
    nr   integer
);

insert into wires_to_numbers(name, nr)
       values ('single', 1),
              ('double', 2),
              ('triple', 3),
              ('quad', 4);

create function number_of_wires(a text) returns integer array as $$
declare
    r integer array;
    t text;
    w wires_to_numbers;
begin
    for t in select unnest(string_to_array(a, ';')) loop
        select * into w from wires_to_numbers where name = t;
        if w is not null
        then
             r = r || w.nr;
        else
            begin
                r = r || t::integer;
            exception when others then
                r = r || null;
            end;
        end if;
    end loop;
    return r;
end;
$$ language plpgsql;
truncate electrical_properties;

insert into electrical_properties (osm_id, frequency, voltage, conductor_bundles, subconductors, power_name, operator, name)
    select l.osm_id, string_to_float_array(tags->'frequency', ';'), string_to_integer_array(tags->'voltage', ';'),
           string_to_integer_array(tags->'cables', ';'), number_of_wires(tags->'wires'),
           tags->'power', tags->'operator', tags->'name'
        from power_line l join osm_tags t on t.osm_id = l.osm_id;

insert into electrical_properties (osm_id, frequency, voltage, power_name, operator, name)
    select s.osm_id, string_to_float_array(tags->'frequency', ';'), string_to_integer_array(tags->'voltage', ';'),
            tags->'power', tags->'operator', tags->'name'
        from power_station s join osm_tags t on t.osm_id = s.osm_id
        where power_name != 'joint';

/* joints are more like lines. */
insert into electrical_properties (osm_id, frequency, voltage, conductor_bundles, subconductors, power_name, operator, name)
    select s.osm_id, string_to_float_array(tags->'frequency', ';'), string_to_integer_array(tags->'voltage', ';'),
           string_to_integer_array(tags->'cables', ';'), number_of_wires(tags->'wires'),
           tags->'power', tags->'operator', tags->'name'
        from power_station s join osm_tags t on t.osm_id = s.osm_id
        where power_name = 'joint';

commit;
