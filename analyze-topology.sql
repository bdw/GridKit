begin transaction;

alter table power_line drop column if exists endpoints;
alter table power_line add column terminals geometry(multipoint);

update power_line set terminals = ST_Union(ST_StartPoint(extent), ST_EndPoint(extent)) where not ST_IsClosed(extent);


drop index if exists power_station_location;
drop index if exists power_line_extent;
drop index if exists power_line_terminals;
create index power_station_location on power_station using gist(location);
create index power_line_extent on power_line using gist(extent);
create index power_line_terminals on power_line using gist(terminals);

/*
drop table if exists geometry_buffer;
create table geometry_buffer (
       osm_id varchar(64),
       geom geometry,
       primary key (osm_id)
);

create index geomotry_buffer_index on geometry_buffer using gist(geom);
insert into geometry_buffer (osm_id, geom)
       select osm_id, ST_Buffer(location, 100)
              from power_station;

insert into geometry_buffer (osm_id, geom)
       select osm_id, ST_Buffer(extent, 50)
              from power_line;
*/
drop table if exists station_line;
create table station_line (
       line_id text,
       station_id text[]
);


/* get all connecting lines connecting stations, without buffering */
insert into station_line (line_id, station_id)
select l.osm_id, array_agg(s.osm_id)
       from power_station s
       join power_line l on ST_Intersects(s.location, l.extent)
       group by l.osm_id
       having count(*) > 1;



copy (
     select sl.line_id, sl.station_id, l.power_name as line_name, s.power_name as station_name, ST_AsText(ST_Centroid(s.location)) as station_location
            from (select line_id, unnest(station_id) as station_id
                         from station_line where array_length(station_id, 1) > 2) as sl
            join power_station s on sl.station_id = s.osm_id
            join power_line   l on sl.line_id     = l.osm_id
            order by sl.line_id
) to '/tmp/station-line-gt-3.csv' with csv header;

/* mergeable lines
select l.osm_id, r.osm_id, ST_AsText(ST_LineMerge(ST_Union(l.extent, r.extent)))
       from power_line l
       join power_line r on l.osm_id != r.osm_id
            and (st_intersects(l.extent, ST_StartPoint(r.extent))
                 or ST_InterSects(l.extent, ST_EndPoint(r.extent)))
       limit 100;
*/
commit;
