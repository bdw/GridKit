-- by step 3a, we've split all lines that intersect with stations.
-- now we also want to shorten them, so we can't have inter-station line intersections.
begin;
drop table if exists truncated_lines;
create table truncated_lines (
    line_id varchar(64),
    station_id text[],
    extent geometry(linestring, 3857),
    areas  geometry(multipolygon, 3857)
);


insert into truncated_lines (line_id, station_id, extent, areas)
    select l.osm_id, array_agg(s.osm_id), l.extent, st_multi(st_union(s.area))
        from power_line l join power_station s on st_intersects(s.area, l.extent)
        where l.osm_id not in (select synth_id from split_lines)
        group by l.osm_id, l.extent
        -- sometimes the difference is complex because merged station area may be overlapping
        -- with the terminals, which means it isn't split in the earlier step; we now silently
        -- ignore this, but that is not the ideal solution.
        having st_geometrytype(st_difference(l.extent, st_union(s.area))) = 'ST_LineString';
/*
update power_line l
   set extent = st_difference(t.extent, t.areas),
       terminals = minimal_terminals(st_difference(t.extent, areas), areas)
    from truncated_lines t
    where t.line_id = l.osm_id a
    and st_geometrytype(st_difference(t.extent, areas)) == 0                      ;
*/
--select 1/0;
commit;
