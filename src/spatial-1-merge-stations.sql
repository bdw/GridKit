/* select all stations that share space and collect them together, probably requires a recursive query of sorts */
begin;
drop table if exists merged_stations;

create table merged_stations (
    station_id integer primary key,
    objects integer array,
    area    geometry(geometry, 3857)
);

/* Recursive union-find implementation. Only feasible becuase this set is initially pretty small */
with recursive overlapping_stations(min_id, objects) as (
    select min(b.station_id), array_agg(b.station_id order by b.station_id)
         from power_station a
         join power_station b on ST_Intersects(a.area, b.area)
         group by a.station_id
         having count(*) > 1
), combinations(min_id, objects) as (
    select * from overlapping_stations
    union
    select min_id, array_agg(distinct station_id order by station_id) from (
        select least(a.min_id, b.min_id), unnest(a.objects || b.objects)
           from combinations a
           join overlapping_stations b on b.objects && a.objects
    ) sq(min_id, station_id) group by sq.min_id
) insert into merged_stations (station_id, objects, area)
    select nextval('station_id'), a.objects, (
           select ST_Union(s.area) from power_station s where s.station_id = any(a.objects)
        )
        from combinations a where not exists (
            select * from combinations b where b.objects @> a.objects and a.objects != b.objects
        );

insert into power_station (station_id, power_name, location, area)
    select station_id, 'merge', ST_Centroid(area), area
         from merged_stations;

insert into osm_objects (power_id, power_type, objects)
    select station_id, 's', source_objects(objects, 's')
        from merged_stations;

delete from power_station s where exists (
    select 1 from merged_stations m where s.station_id = any(m.objects)
);

commit;
