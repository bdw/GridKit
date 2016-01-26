begin;
drop table if exists problem_lines;
drop table if exists topology_edges;
drop table if exists heuristic_vertices;
drop table if exists heuristic_links;
create table problem_lines (
       line_id varchar(64),
       station_id text[],
       line_extent geometry(linestring, 3857),
       line_terminals geometry(geometry, 3857),
       station_area geometry(geometry, 3857)
);


create table topology_edges (
    line_id varchar(64),
    station_id text[],
    line_extent geometry(linestring, 3857),
    station_locations geometry(point, 3857) array
);

create table heuristic_vertices (
    osm_id varchar(64),
    location    geometry(point, 4326),
    primary key (osm_id)
);

create table heuristic_links (
    line_id varchar(64),
    from_id varchar(64),
    to_id   varchar(64),
    line    geometry(linestring, 4326),
    length  real,
    primary key (line_id)
);

insert into problem_lines (line_id, station_id, line_extent, line_terminals, station_area)
     select l.osm_id as line_id, array_agg(s.osm_id) as station_id, l.extent, l.terminals, st_union(s.area)
            from power_line l join power_station s on st_intersects(s.area, l.terminals)
            group by l.osm_id, l.extent, l.terminals having count(*) > 2;


insert into topology_edges (line_id, station_id, line_extent, station_locations)
    select l.osm_id, array_agg(s.osm_id), l.extent, array_agg(s.location)
        from power_line l join power_station s on st_intersects(s.area, l.terminals)
        group by l.osm_id, l.extent having count(*) <= 2;

insert into heuristic_vertices (osm_id, location)
    select distinct unnest(station_id), st_transform(unnest(station_locations), 4326) from topology_edges;

insert into heuristic_links (line_id, from_id, to_id, line, length)
    select line_id, station_id[1], station_id[2],
           st_transform(st_makeline(station_locations[1], station_locations[2]), 4326),
           st_length(st_transform(line_extent, 4326)::geography) from topology_edges;

commit;
