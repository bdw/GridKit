/* select all stations that share space and collect them together, probably requires a recursive query of sorts */
begin;
drop table if exists merged_stations;

create table merged_stations (
    synth_id varchar(64),
    objects varchar(64) array,
    area    geometry(geometry, 3857)
);

/* Recursive union-find implementation. Only feasible becuase this set is initially pretty small */
with recursive overlapping_stations(osm_id, objects) as (
    select min(b.osm_id) as osm_id, array_agg(b.osm_id order by b.osm_id) as objects
         from power_station a
         join power_station b on ST_Intersects(a.area, b.area)
         group by a.osm_id
         having count(*) > 1
), combinations as (
    select * from overlapping_stations
    union
    select osm_id, array_agg(distinct e order by e) from (
        select least(a.osm_id, b.osm_id) as osm_id, unnest(a.objects || b.objects) as e
           from combinations as a join overlapping_stations b on b.objects && a.objects
    ) sq group by sq.osm_id
) insert into merged_stations (synth_id, objects, area)
    select concat('m', nextval('synthetic_objects')), objects,
           (select ST_Union(b.area) from power_station b where b.osm_id in (select unnest(a.objects))) as area
                from combinations a where not exists (
                   select * from combinations b where b.objects @> a.objects and a.objects != b.objects
                );

insert into power_station (osm_id, power_name, location, area)
    select synth_id, 'merge', ST_Centroid(area), area
         from merged_stations;

insert into osm_objects (osm_id, objects)
    select synth_id, source_objects(objects) from merged_stations;

delete from power_station where osm_id in (select unnest(objects) from merged_stations);

commit;
