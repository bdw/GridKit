begin;
drop table if exists problem_lines;
drop table if exists topology_edges;
drop table if exists topology_nodes;
drop table if exists dangling_lines;

create table problem_lines (
    line_id integer,
    station_id integer array,
    line_extent geometry(linestring, 3857),
    line_terminals geometry(geometry, 3857),
    station_area geometry(geometry, 3857)
);

create table dangling_lines (
    line_id integer,
    extent geometry(linestring, 3857)
);

create table topology_edges (
    line_id integer primary key,
    station_id integer array,
    line_extent geometry(linestring, 3857),
    direct_line geometry(linestring, 3857),
    topology_name varchar(64)
);

create table topology_nodes (
    station_id integer primary key,
    line_id integer array,
    station_location geometry(point, 3857),
    topology_name varchar(64)
);


create index topology_edges_station_id on topology_edges using gin(station_id);
create index topology_nodes_line_id    on topology_nodes using gin(line_id);

insert into problem_lines (line_id, station_id, line_extent, line_terminals, station_area)
    select line_id, array_agg(s.station_id), l.extent, l.terminals, st_union(s.area)
        from power_line l join power_station s on st_intersects(s.area, l.terminals)
        group by l.line_id, l.extent, l.terminals having count(*) > 2;

insert into topology_edges (line_id, station_id, line_extent, topology_name)
    select l.line_id, array_agg(s.station_id), l.extent, l.power_name
        from power_line l join power_station s on st_intersects(s.area, l.terminals)
        group by l.line_id having count(*) = 2;

insert into topology_nodes (station_id, line_id, station_location, topology_name)
    select s.station_id, array_agg(e.line_id), s.location, s.power_name
        from power_station s
        join topology_edges e on s.station_id = any(e.station_id)
        group by s.station_id;

update topology_edges e set direct_line = st_makeline(a.station_location, b.station_location)
     from topology_nodes a, topology_nodes b
     where e.station_id[1] = a.station_id and e.station_id[2] = b.station_id;

insert into dangling_lines (line_id, extent)
    select line_id, extent from power_line where line_id not in (
       select line_id from topology_edges
       union all
       select line_id from problem_lines
   );


commit;
