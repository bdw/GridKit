begin;
/* functions */
drop function if exists array_remove(anyarray, anyarray);
drop function if exists array_replace(anyarray, anyarray, anyarray);
drop function if exists array_sym_diff(anyarray, anyarray);
drop function if exists array_merge(anyarray, anyarray);
drop function if exists array_most_common(anyarray);

drop function if exists buffered_terminals(geometry(linestring));
drop function if exists buffered_station_point(geometry(point));
drop function if exists way_station_area(geometry(linestring));
drop function if exists buffered_station_area(geometry(polygon));
drop function if exists connect_lines(a geometry(linestring), b geometry(linestring));
drop function if exists connect_lines_terminals(geometry, geometry);
drop function if exists reuse_terminal(geometry, geometry, geometry);
drop function if exists minimal_terminals(geometry, geometry, geometry);



create function array_remove(a anyarray, b anyarray) returns anyarray as $$
begin
    return array(select v from (select unnest(a)) t(v) where not v = any(b));
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


create function array_most_common(a anyarray) returns anyelement as $$
begin
        return v from (
           select unnest(a)
        ) t(v) group by v order by count(*) desc limit 1;
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

create function connect_lines_terminals(a geometry(multipolygon), b geometry(multipolygon))
    returns geometry(multipolygon) as $$
begin
    return case when st_intersects(st_geometryn(a, 1), st_geometryn(b, 1)) then st_union(st_geometryn(a, 2), st_geometryn(b, 2))
                when st_intersects(st_geometryn(a, 2), st_geometryn(b, 1)) then st_union(st_geometryn(a, 1), st_geometryn(b, 2))
                when st_intersects(st_geometryn(a, 1), st_geometryn(b, 2)) then st_union(st_geometryn(a, 2), st_geometryn(b, 1))
                                                                           else st_union(st_geometryn(a, 1), st_geometryn(b, 1)) end;
end;
$$ language plpgsql;



create function reuse_terminal(point geometry, terminals geometry, line geometry) returns geometry as $$
declare
    max_buffer float;
begin
    max_buffer = least(st_length(line) / 3.0, 50.0);
    if st_geometrytype(terminals) = 'ST_MultiPolygon' then
        if st_distance(st_geometryn(terminals, 1), point) < 1 then
            return st_geometryn(terminals, 1);
        elsif st_distance(st_geometryn(terminals, 2), point) < 1 then
            return st_geometryn(terminals, 2);
        else
            return st_buffer(point, max_buffer);
        end if;
    else
        return st_buffer(point, max_buffer);
    end if;
end;
$$ language plpgsql;

create function minimal_terminals(line geometry, area geometry, terminals geometry) returns geometry as $$
declare
    start_term geometry;
    end_term   geometry;
begin
    start_term = case when st_distance(st_startpoint(line), area) < 1 then st_buffer(st_startpoint(line), 1)
                      else reuse_terminal(st_startpoint(line), terminals, line) end;
    end_term   = case when st_distance(st_endpoint(line), area) < 1 then st_buffer(st_endpoint(line), 1)
                      else reuse_terminal(st_endpoint(line), terminals, line) end;
    return st_union(start_term, end_term);
end;
$$ language plpgsql;

commit;
