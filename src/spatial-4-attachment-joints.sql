begin;
-- Get attachment points, split lines, insert stations for attachment points
drop table if exists line_attachments;
drop table if exists attachment_stations;
drop table if exists attachment_split_lines;
drop table if exists attached_lines;

create table line_attachments (
    source_id   integer primary key,
    attach_id   integer array,
    extent      geometry(linestring, 3857),
    attachments geometry(multipolygon, 3857)
);

create table attachment_stations (
    station_id integer not null,
    area       geometry(polygon, 3857),
    objects    integer array
);

create table attachment_split_lines (
    new_id  integer primary key,
    old_id  integer not null,
    extent  geometry(linestring, 3857)
);

create table attached_lines (
    line_id    integer primary key,
    station_id integer array,
    old_extent geometry(linestring, 3857),
    new_extent geometry(linestring, 3857),
    areas  geometry(multipolygon, 3857)
);

-- Find all lines that other lines are attaching to
insert into line_attachments (source_id, attach_id, extent, attachments)
    select b.line_id, array_agg(distinct a.line_id), b.extent,
           st_multi(st_union(st_buffer(st_intersection(a.terminals, b.extent), 1)))
       from power_line a join power_line b
           on st_intersects(a.terminals, b.extent)
              and not st_intersects(a.terminals, b.terminals)
       group by b.line_id, b.extent;

-- Create segments for the split line
insert into attachment_split_lines (new_id, old_id, extent)
    select nextval('line_id'), source_id,
          (st_dump(st_difference(extent, attachments))).geom
        from line_attachments;

-- Create a station for each attachment point
insert into attachment_stations (station_id, objects, area)
    select nextval('station_id'), attach_id || source_id,
           (st_dump(attachments)).geom
        from line_attachments;

-- Compute which lines to extend to attach to the power lines
insert into attached_lines (line_id, old_extent, new_extent, station_id, areas)
    select l.line_id, l.extent, l.extent, array_agg(s.station_id), st_multi(st_union(s.area))
        from power_line l
        join line_attachments a on l.line_id = any(a.attach_id)
        join attachment_stations s on a.source_id = any(s.objects)
        group by l.line_id;

-- Extend the attached lines to connect cleanly with the attachment station.
-- Two queries are easier than a single 4-way monster query
update attached_lines
    set new_extent = connect_lines(st_shortestline(st_startpoint(new_extent), areas), new_extent)
    where st_intersects(st_buffer(st_startpoint(new_extent), 50), areas)
        and st_distance(st_startpoint(new_extent), areas) > 1;

update attached_lines
    set new_extent = connect_lines(new_extent, st_shortestline(st_endpoint(new_extent), areas))
    where st_intersects(st_buffer(st_endpoint(new_extent), 50), areas)
        and st_distance(st_endpoint(new_extent), areas) > 1;

-- insert joints
insert into power_station (station_id, power_name, location, area)
    select station_id, 'joint', st_centroid(area), area
        from attachment_stations;

-- replace power lines
insert into power_line (line_id, power_name, extent, terminals)
    select s.new_id, l.power_name, s.extent,
           minimal_terminals(s.extent, a.attachments, l.terminals)
        from attachment_split_lines s
        join line_attachments a on a.source_id = s.old_id
        join power_line l on l.line_id = s.old_id;


delete from power_line l where exists  (
    select 1 from line_attachments a where a.source_id = l.line_id
);

-- extend their lengths
update power_line l
    set extent = a.new_extent,
        terminals = minimal_terminals(a.new_extent, a.areas, l.terminals)
    from attached_lines a where a.line_id = l.line_id;

-- track new lines
insert into osm_objects(power_id, power_type, objects)
    select new_id, 'l', source_objects(array[old_id], 'l') from attachment_split_lines;

-- and stations
insert into osm_objects (power_id, power_type, objects)
    select station_id, 's', source_objects(objects, 'l') from attachment_stations;



commit;
