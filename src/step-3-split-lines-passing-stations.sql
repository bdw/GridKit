begin;
drop table if exists split_lines;
create table split_lines (
       source_id text,
       station_id text[],
       segment geometry(linestring, 3857)
);
with line_intersections as (
     select l.osm_id as source_id,
            array_agg(s.osm_id) as station_id,
            st_union(st_intersection(l.extent, s.area)) as intersection
            from power_line l join power_station s on ST_Intersects(l.extent, s.area) and not ST_Intersects(l.terminals, s.area)
            group by source_id
) insert into split_lines (source_id, station_id, segment)
     select i.source_id, i.station_id, (st_dump(st_difference(l.extent, i.intersection))).geom as segment
          from line_intersections i join power_line l on i.source_id = l.osm_id;

insert into power_line (osm_id, power_name, tags, extent, terminals, objects)
       select concat('s', nextval('synthetic_objects')) as osm_id, l.power_name, l.tags, s.segment,
              ST_Buffer(ST_Union(ST_StartPoint(s.segment), ST_EndPoint(s.segment)), 100), array[s.source_id]
              from split_lines s join power_line l on l.osm_id = s.source_id;

delete from power_line where osm_id in (select source_id from split_lines);
commit;
