begin transaction;
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

/* mergeable lines */
select l.osm_id, r.osm_id, ST_AsText(ST_LineMerge(ST_Union(l.extent, r.extent)))
       from power_line l
       join power_line r on l.osm_id != r.osm_id
            and (st_intersects(l.extent, ST_StartPoint(r.extent))
                 or ST_InterSects(l.extent, ST_EndPoint(r.extent)))
       limit 100;
commit;
