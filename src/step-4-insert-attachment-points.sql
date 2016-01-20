/* a ends on line b */
begin;
/* Get attachment points, split lines, insert stations for attachment points */
drop table if exists line_attachments;
drop table if exists attachment_stations;
drop table if exists attachment_split_lines;

create table line_attachments (
    source_id   varchar(64),
    attach_id   text[],
    extent      geometry(linestring, 3857),
    attachments geometry(multipolygon, 3857),
    primary key (source_id)
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

insert into line_attachments (source_id, attach_id, extent, attachments)
    select b.osm_id, array_agg(distinct a.osm_id), b.extent,
           st_multi(st_union(st_buffer(st_intersection(a.terminals, b.extent), 1)))
       from power_line a join power_line b
           on st_intersects(a.terminals, b.extent)
              and not st_intersects(a.terminals, b.terminals)
       group by b.osm_id, b.extent;

insert into attachment_split_lines (synth_id, source_id, extent)
    select concat('z', nextval('synthetic_objects')), source_id,
           (st_dump(st_difference(extent, attachments))).geom
        from line_attachments;

insert into attachment_stations (synth_id, objects, area)
    select concat('a', nextval('synthetic_objects')), attach_id || source_id::text,
           (st_dump(attachments)).geom
        from line_attachments;


insert into power_line (osm_id, power_name, tags, objects, extent, terminals)
    -- todo, reduce objects to source objects
    select s.synth_id, l.power_name, l.tags, source_line_objects(array[s.source_id]),
           s.extent, minimal_terminals(s.extent, a.attachments) as terminals
        from attachment_split_lines s
        join line_attachments a on a.source_id = s.source_id
        join power_line l on l.osm_id = s.source_id;

insert into power_station (osm_id, power_name, objects, location, area)
    select synth_id, 'attachment', source_line_objects(objects), st_centroid(area), area
        from attachment_stations;

delete from power_line where osm_id in (
    select source_id from line_attachments
);

commit;
