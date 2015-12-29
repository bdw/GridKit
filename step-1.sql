/* select all stations that share space and collect them together, probably requires a recursive query of sorts */
with overlapping_stations as (
        select array_agg(b.osm_id order by b.osm_id) as objects, ST_Union(b.area) as area
                from power_station a
                join power_station b on ST_Intersects(a.area, b.area)
                group by a.osm_id
                having count(*) > 1
) select distinct objects from overlapping_stations;
