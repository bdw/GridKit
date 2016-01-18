/* a ends on line b */
begin;
/* Get attachment points, split lines, insert stations for attachment points */
drop table if exists attached_lines;
create table attached_lines (
        source_id text,
        attach_id text[],
        attachments geometry(geometry, 3857),
        segments    geometry(geometry, 3857)
);
with line_attachments as (
        select b.osm_id as line_id, array_agg(distinct a.osm_id order by a.osm_id) as attach_id, st_union(st_intersection(a.terminals, st_buffer(b.extent, 1))) as attachments
                from power_line a join power_line b
                        on ST_Intersects(a.terminals, b.extent) and not ST_Intersects(a.terminals, b.terminals)
                group by b.osm_id
) insert into attached_lines (source_id, attach_id, attachments, segments)
        select line_id, attach_id, attachments, st_difference(l.extent, attachments) as segments from line_attachments a join power_line l on l.osm_id = a.line_id;

with line_splits as (
        select l.power_name, l.tags, l.objects, (ST_Dump(a.segments)).geom as segment
                from attached_lines a join power_line l on l.osm_id = a.source_id
)
insert into power_line (osm_id, power_name, tags, objects, extent, terminals)
    -- todo, create synthetic ids prior to inserting power lines for better accountability
    select concat('z', nextval('synthetic_objects')) as osm_id,
           power_name, tags, objects, segment as extent,
           buffered_terminals(segment) as terminals
           from line_splits;


with join_points as (
        select (ST_Dump(attachments)).geom as area, attach_id || source_id as objects
                from attached_lines
)
insert into power_station (osm_id, power_name, objects, location, area)
        select concat('a', nextval('synthetic_objects')) as osm_id, 'attachment', objects, st_centroid(area) as location, area
                from join_points;
delete from power_line where osm_id in (select source_id from attached_lines);

commit;
