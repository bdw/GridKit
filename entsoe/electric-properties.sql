begin;
drop table if exists source_station_properties;
drop table if exists source_line_properties;
drop function if exists line_properties_for_object(integer,jsonb);
drop function if exists line_properties_for_source(integer,text);
drop function if exists line_properties_for_join(integer,jsonb);
drop table if exists line_properties_conflicts;
drop table if exists computed_line_properties;
drop function if exists station_properties_for_object(integer,jsonb);
drop function if exists station_properties_for_source(integer,text);
drop function if exists station_properties_for_merge(integer,jsonb);
drop table if exists computed_station_properties;

create table source_station_properties (
    import_id integer primary key,
    symbol   text,
    name     text,
    capacity numeric,
    under_construction boolean
);

create table source_line_properties (
    import_id integer primary key,
    name text,
    frequency integer,
    voltage integer,
    circuits integer,
    under_construction boolean,
    underground boolean
);

create table computed_line_properties (
    line_id integer primary key,
    voltage integer,
    frequency integer,
    circuits integer,
    under_construction boolean,
    underground boolean
);

create table line_properties_conflicts (
    line_id integer not null,
    conflicting_objects jsonb,
    conflicting_properties computed_line_properties array
);

create table computed_station_properties (
   station_id integer primary key,
   symbol     text,
   name       text,
   capacity   numeric,
   under_construction boolean
);

insert into source_station_properties (import_id, symbol, name, capacity, under_construction)
   select import_id, properties->'symbol', properties->'name_all', (properties->'mw')::numeric,
           (properties->'under_construction')::boolean
            from features f where st_geometrytype(f.geometry) = 'ST_Point';

insert into source_line_properties
       (import_id, name, frequency, voltage, circuits, under_construction, underground)
    select import_id, properties->'text_',
           case when substring(properties->'symbol', 1, 7) = 'DC-Line' then 0 else 50 end,
           substring(properties->'voltagelevel' from '^[0-9]+')::int,
           (properties->'numberofcircuits')::int,
           (properties->'underconstruction')::bool,
           (properties->'underground')::bool
           from features f where st_geometrytype(f.geometry) = 'ST_LineString';



create function line_properties_for_object(line_id integer, obj jsonb) returns computed_line_properties as $$
begin
    return case when obj ? 'source' then line_properties_for_source(line_id, obj->>'source')
                when obj ? 'split'  then line_properties_for_object(line_id, obj->'split'->0)
                when obj ? 'join'   then line_properties_for_join(line_id, obj) end;
end;            
$$ language plpgsql;

create function line_properties_for_source(line_id integer, source_id text) returns computed_line_properties as $$
begin
     return row(line_id, voltage, frequency, circuits, under_construction, underground)
            from source_line_properties where import_id = source_id::integer;
end;
$$ language plpgsql;


create function line_properties_for_join(line_id integer, obj jsonb) returns computed_line_properties as $$
declare
    raw_properties computed_line_properties array;
    have_conflicts integer;
begin
    raw_properties = array(select line_properties_for_object(line_id, prt) from jsonb_array_elements(obj->'join') ar(prt));
    have_conflicts = count(*) from (
         select voltage, frequency, circuits, under_construction, underground from unnest(raw_properties) r(_line_id, voltage, frequency, circuits, under_construction, underground)
                group by voltage, frequency, circuits, under_construction, underground
    ) _g;
    if have_conflicts > 1 then
        insert into line_properties_conflicts (line_id, conflicting_objects, conflicting_properties) values (line_id, obj->'join', raw_properties);
    end if;
    -- TODO find and record conflicts
    return raw_properties[1];
end;
$$ language plpgsql;

create function station_properties_for_object(station_id integer, obj jsonb) returns computed_station_properties as $$
begin
    if not (obj ? 'source' or obj ? 'merge')
    then
        raise exception 'cannot parse %', obj;
    end if;
    return case when obj ? 'source' then station_properties_for_source(station_id, obj->>'source')
                when obj ? 'merge'  then station_properties_for_merge(station_id, obj) end;
end;
$$ language plpgsql;

create function station_properties_for_source(station_id integer, source_id text) returns computed_station_properties as $$
begin
    return row(station_id, symbol, name, capacity, under_construction) from source_station_properties where import_id = source_id::integer;
end;
$$ language plpgsql;

create function station_properties_for_merge(station_id integer, obj jsonb) returns computed_station_properties as $$
declare
    raw_data computed_station_properties array;
    have_conflicts integer;
begin
    raw_data = array(select station_properties_for_object(station_id, prt) from jsonb_array_elements(obj->'merge') ar(prt));
    return raw_data[1];
end;
$$ language plpgsql;


insert into computed_line_properties
    select (line_properties_for_object(e.line_id, o.objects)).* from source_objects o join topology_edges e on e.line_id = o.power_id and o.power_type = 'l';

insert into computed_station_properties
    select (station_properties_for_object(n.station_id, o.objects)).*
      from topology_nodes n join source_objects o on o.power_id = n.station_id and o.power_type = 's'
     where n.topology_name != 'joint';

commit;
