begin;
drop table if exists electric_tags;
drop table if exists wires_to_numbers;
drop function if exists string_to_integer_array(text,text);
drop function if exists string_to_float_array(text,text);
drop function if exists number_of_wires(text);

create table electric_tags (
    source_id varchar(64) primary key,
    power_name varchar(64) not null,
    voltage integer array,
    frequency float array,
    cables integer array,
    wires integer array
);

create index electric_tags_power_name_idx on electric_tags (power_name);


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


insert into electric_tags (source_id, power_name, voltage, frequency, cables, wires)
   select source_id, tags->'power',
          string_to_integer_array(tags->'voltage',';'),
          string_to_float_array(tags->'frequency',';'),
          string_to_integer_array(tags->'cables',';'),
          number_of_wires(tags->'wires')
       from source_tags;

commit;
