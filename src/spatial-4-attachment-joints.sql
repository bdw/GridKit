/* a ends on line b */
begin;
/* Get attachment points, split lines, insert stations for attachment points */
drop table if exists line_attachments;
drop table if exists attachment_stations;
drop table if exists attachment_split_lines;
drop table if exists attached_lines;

create table line_attachments (
    source_id   varchar(64),
    attach_id   varchar(64) array,
    extent      geometry(linestring, 3857),
    attachments geometry(multipolygon, 3857),
    primary key (source_id)
);

create table attachment_stations (
    synth_id varchar(64),
    area     geometry(polygon, 3857),
    objects  varchar(64) array
);

create table attachment_split_lines (
    synth_id  varchar(64),
    source_id varchar(64),
    extent    geometry(linestring, 3857)
);

create table attached_lines (
    line_id varchar(64),
    station_id varchar(64) array,
    extent geometry(linestring, 3857),
    areas  geometry(multipolygon, 3857),
    primary key (line_id)
);

/* Find all lines that other lines are attaching to */
insert into line_attachments (source_id, attach_id, extent, attachments)
    select b.osm_id, array_agg(distinct a.osm_id), b.extent,
           st_multi(st_union(st_buffer(st_intersection(a.terminals, b.extent), 1)))
       from power_line a join power_line b
           on st_intersects(a.terminals, b.extent)
              and not st_intersects(a.terminals, b.terminals)
       group by b.osm_id, b.extent;

/* Create segments for the split line */
insert into attachment_split_lines (synth_id, source_id, extent)
    select concat('z', nextval('synthetic_objects')), source_id,
           (st_dump(st_difference(extent, attachments))).geom
        from line_attachments;

/* Create a station for each attachment point */
insert into attachment_stations (synth_id, objects, area)
    select concat('a', nextval('synthetic_objects')), attach_id || source_id,
           (st_dump(attachments)).geom
        from line_attachments;

/* Compute which lines to extend to attach to the power lines */
insert into attached_lines (line_id, extent, station_id, areas)
    select l.osm_id, l.extent, array_agg(s.synth_id), st_multi(st_union(s.area))
        from power_line l
        join line_attachments a on l.osm_id = any(a.attach_id)
        join attachment_stations s on a.source_id = any(s.objects)
        group by l.osm_id;

/* Extend the attached lines to connect cleanly with the attachment station. 
 * Two queries are easier than a single 4-way monster query */
update attached_lines
    set extent = connect_lines(st_shortestline(st_startpoint(extent), areas), extent)
    where st_intersects(st_buffer(st_startpoint(extent), 50), areas)
        and st_distance(st_startpoint(extent), areas) > 1;

update attached_lines
    set extent = connect_lines(extent, st_shortestline(st_endpoint(extent), areas))
    where st_intersects(st_buffer(st_endpoint(extent), 50), areas)
        and st_distance(st_endpoint(extent), areas) > 1;

/* Create power lines and stations */
insert into power_line (osm_id, power_name, extent, terminals)
    select s.synth_id, l.power_name, s.extent,
           minimal_terminals(s.extent, a.attachments, l.terminals)
        from attachment_split_lines s
        join line_attachments a on a.source_id = s.source_id
        join power_line l on l.osm_id = s.source_id;

insert into power_station (osm_id, power_name, location, area)
    select synth_id, 'joint', st_centroid(area), area
        from attachment_stations;

insert into osm_objects(osm_id, objects)
    select synth_id, source_objects(array[source_id]) from attachment_split_lines;

insert into osm_objects (osm_id, objects)
    select synth_id, source_objects(objects) from attachment_stations;



update power_line l
    set extent = a.extent,
        terminals = minimal_terminals(a.extent, a.areas, l.terminals)
    from attached_lines a where a.line_id = l.osm_id;

delete from power_line where osm_id in (
    select source_id from line_attachments
);

commit;
