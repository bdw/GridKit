begin;
/* functions */
drop function if exists array_remove(anyarray, anyarray);
drop function if exists array_replace(anyarray, anyarray, anyarray);
drop function if exists array_sym_diff(anyarray, anyarray);
drop function if exists array_merge(anyarray, anyarray);

drop function if exists buffered_terminals(geometry(linestring));
drop function if exists buffered_station_point(geometry(point));
drop function if exists way_station_area(geometry(linestring));
drop function if exists buffered_station_area(geometry(polygon));
drop function if exists connect_lines(a geometry(linestring), b geometry(linestring));
drop function if exists default_radius(geometry);
drop function if exists minimal_radius(geometry, geometry, int array);
drop function if exists track_objects(integer array, char(1), text);

create function array_remove(a anyarray, b anyarray) returns anyarray as $$
begin
    return array((select unnest(a) except select unnest(b)));
end;
$$ language plpgsql;

create function array_replace(a anyarray, b anyarray, n anyarray) returns anyarray as $$
begin
    return array((select unnest(a) except select unnest(b) union select unnest(n)));
end;
$$ language plpgsql;

create function array_sym_diff(a anyarray, b anyarray) returns anyarray as $$
begin
    return array(((select unnest(a) union select unnest(b))
                   except
                  (select unnest(a) intersect select unnest(b))));
end;
$$ language plpgsql;

create function array_merge(a anyarray, b anyarray) returns anyarray as $$
begin
    return array(select unnest(a) union select unnest(b));
end;
$$ language plpgsql;


create function buffered_terminals(line geometry(linestring)) returns geometry(linestring) as $$
begin
    return st_buffer(st_union(st_startpoint(line), st_endpoint(line)), least(50.0, st_length(line)/3.0));
end
$$ language plpgsql;

create function buffered_station_point(point geometry(point)) returns geometry(polygon) as $$
begin
    return st_buffer(point, 50);
end;
$$ language plpgsql;

create function buffered_station_area(area geometry(polygon)) returns geometry(polygon) as $$
begin
    return st_convexhull(st_buffer(area, least(sqrt(st_area(area)), 100)));
end;
$$ language plpgsql;

create function way_station_area(line geometry(linestring)) returns geometry(polygon) as $$
begin
     return case when st_isclosed(line) then st_makepolygon(line)
                 when st_npoints(line) = 2 then st_buffer(line, 1)
                 else st_makepolygon(st_addpoint(line, st_startpoint(line))) end;
end
$$ language plpgsql;

create function connect_lines (a geometry(linestring), b geometry(linestring)) returns geometry(linestring) as $$
begin
    -- select the shortest line that comes from joining the lines
     -- in all possible directions
    return (select e from (
                select unnest(
                         array[st_makeline(a, b),
                               st_makeline(a, st_reverse(b)),
                               st_makeline(st_reverse(a), b),
                               st_makeline(st_reverse(a), st_reverse(b))]) e) f
                order by st_length(e) limit 1);
end;
$$ language plpgsql;

create function default_radius(line geometry) returns int array as $$
declare
    r numeric;
begin
    r = least(floor(st_length(line)/3.0), 50);
    return array[r,r];
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

commit;
