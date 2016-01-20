/* a ends on line b */
begin;
/* Get attachment points, split lines, insert stations for attachment points */
drop table if exists line_attachments;
drop table if exists attachment_stations;
drop table if exists attachment_split_lines;

create table line_attachments (
    source_id text,
    attach_id text[],
    attachments geometry(geometry, 3857),
    segments    geometry(geometry, 3857)
);

create table attachment_stations (
    synth_id varchar(64),
    area     geometry(polygon, 3857),
    objects  text[]
);

create table attachment_split_lines (
    synth_id  varchar(64),
    source_id varchar(64),
    extent    geometry(linestring, 3857)
);

with attached_lines as (
    select b.osm_id as line_id, array_agg(distinct a.osm_id order by a.osm_id) as attach_id,
            st_union(st_intersection(a.terminals, st_buffer(b.extent, 1))) as attachments
        from power_line a join power_line b
            on ST_Intersects(a.terminals, b.extent) and not ST_Intersects(a.terminals, b.terminals)
            group by b.osm_id
) insert into line_attachments (source_id, attach_id, attachments, segments)
     select line_id, attach_id, attachments, st_difference(l.extent, attachments) as segments
         from attached_lines a join power_line l on l.osm_id = a.line_id;

insert into attachment_split_lines (synth_id, source_id, extent)
    select concat('z', nextval('synthetic_objects')), source_id, (ST_Dump(segments)).geom
        from line_attachments;

insert into attachment_stations (synth_id, objects, area)
    select concat('a', nextval('synthetic_objects')), attach_id || source_id ,(ST_Dump(attachments)).geom
        from line_attachments;


insert into power_line (osm_id, power_name, tags, objects, extent, terminals)
    -- todo, reduce objects to source objects
    select a.synth_id, l.power_name, l.tags, source_line_objects(array[a.source_id]),
           a.extent, buffered_terminals(a.extent) as terminals
        from attachment_split_lines a join power_line l on l.osm_id = a.source_id;

insert into power_station (osm_id, power_name, objects, location, area)
    select synth_id, 'attachment', source_line_objects(objects), st_centroid(area), area
        from attachment_stations;



delete from power_line where osm_id in (select source_id from attached_lines);
commit;
