-- script to transfer features to gridkit power stations and lines
begin;
drop view if exists power_line_terminals;
drop table if exists power_station;
drop table if exists power_line;
drop table if exists power_generator;
drop table if exists source_ids;
drop table if exists source_objects;

drop sequence if exists station_id;
drop sequence if exists line_id;
drop function if exists minimal_radius(geometry, geometry, int array);
drop function if exists connect_lines(geometry,geometry);
drop function if exists track_objects(integer array, char(1), text);

create function connect_lines (a geometry(linestring), b geometry(linestring)) returns geometry(linestring) as $$
begin
    -- select the shortest line that comes from joining the lines
     -- in all possible directions
    return e from unnest(array[st_makeline(a, b),
                               st_makeline(a, st_reverse(b)),
                               st_makeline(st_reverse(a), b),
                               st_makeline(st_reverse(a), st_reverse(b))]) f(e)
              order by st_length(e) asc limit 1;
end;
$$ language plpgsql;

create function minimal_radius(line geometry, area geometry, radius int array) returns int array as $$
begin
    return array[case when st_dwithin(st_startpoint(line), area, 1) then 1 else radius[1] end,
                 case when st_dwithin(st_endpoint(line), area, 1) then 1 else radius[2] end];
end;
$$ language plpgsql;


create function track_objects(pi integer array, pt char(1), op text) returns jsonb
as $$
begin
    return json_build_object(op, to_json(array(select objects from source_objects where power_id = any(pi) and power_type = pt)))::jsonb;
end;
$$ language plpgsql;


create table power_station (
    station_id integer primary key,
    power_name varchar(64) not null,
    location geometry(point, 3857),
    area geometry(polygon, 3857)
);

create index power_station_area on power_station using gist (area);

create table power_line (
    line_id integer primary key,
    power_name varchar(64) not null,
    extent    geometry(linestring, 3857),
    radius    integer array[2]
);

create index power_line_extent_idx on power_line using gist(extent);
create index power_line_startpoint_idx on power_line using gist(st_startpoint(extent));
create index power_line_endpoint_idx on power_line using gist(st_endpoint(extent));

create table power_generator (
    generator_id integer primary key,
    location geometry(point, 3857),
    tags hstore
);

create index power_generator_location_idx on power_generator using gist(location);

create sequence line_id;
create sequence station_id;
create sequence generator_id;

create table source_ids (
    power_id integer not null,
    power_type char(1) not null,
    import_id integer not null,
    primary key (power_id, power_type)
);

create table source_objects (
    power_id integer not null,
    power_type char(1) not null,
    objects jsonb,
    primary key (power_id, power_type)
);

insert into source_ids (power_id, power_type, import_id)
    select nextval('station_id'), 's', import_id
        from features where st_geometrytype(geometry) = 'ST_Point';

insert into source_ids (power_id, power_type, import_id)
    select nextval('line_id'), 'l', import_id
        from features where st_geometrytype(geometry) = 'ST_LineString';

insert into source_objects (power_id, power_type, objects)
    select power_id, power_type, json_build_object('source', import_id::text)::jsonb
        from source_ids;

insert into power_station (station_id, power_name, location, area)
    select i.power_id, properties->'symbol', st_transform(geometry, 3857), st_buffer(st_transform(geometry, 3857), 50)
        from features f join source_ids i on i.import_id = f.import_id where i.power_type = 's';

insert into power_line (line_id, power_name, extent, radius)
     select i.power_id, 'line', st_transform(geometry, 3857), array[750,750]
       from features f
       join source_ids i on i.import_id = f.import_id
      where i.power_type = 'l';

insert into power_generator (generator_id, location, tags)
     select nextval('generator_id'), st_transform(geometry, 3857), properties
       from features
      where st_geometrytype(geometry) = 'ST_Point'
        and properties->'symbol' not in (
                'Substation',
                'Substation, under construction',
                'Converter Station',
                'Converter Station, under construction',
                'Converter Station Back-to-Back'
            );

commit;
