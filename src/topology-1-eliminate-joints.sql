begin;
/* joints are 'virtual' station types, and we really want as few as them as possible, so we try to eliminate them here */
drop table if exists dangling_lines;
drop table if exists redundant_joints;
drop table if exists rejoin_pairs;
drop table if exists rejoin_sets;
drop table if exists rejoin_lines;

create table dangling_lines (
    line_id varchar(64),
    extent  geometry(linestring, 3857),
    primary key (line_id)
);

create table redundant_joints (
    station_id varchar(64),
    line_id    varchar(64) array[2],
    line_extent geometry(linestring, 3857) array[2]
);

create table rejoin_pairs (
    src varchar(64),
    dst varchar(64)
);

create table rejoin_sets (
    v varchar(64),
    k varchar(64),
    e geometry(linestring, 3857),
    t geometry(multipolygon, 3857),
    primary key (v)
);

create table rejoin_lines (
   synth_id  varchar(64),
   source_id varchar(64) array,
   extent    geometry(linestring, 3857),
   terminals geometry(multipolygon, 3857)
);

create index rejoin_sets_k on rejoin_sets using btree(k);

insert into dangling_lines (line_id, extent)
    select l.osm_id, l.extent from power_line l
           left join power_station s on st_intersects(s.area, l.terminals)
           group by l.osm_id, l.extent having count(s.osm_id) < 2;

delete from power_line where osm_id in (select line_id from dangling_lines);

insert into redundant_joints (station_id, line_id, line_extent)
    select s.osm_id, array_agg(l.osm_id order by l.osm_id), array_agg(l.extent)
        from power_station s join power_line l on st_intersects(s.area, l.terminals)
        where s.power_name = 'joint' group by s.osm_id having count(*) <= 2;

delete from power_station where osm_id in (select station_id from redundant_joints);

insert into rejoin_pairs (src, dst)
   select line_id[1], line_id[2] from redundant_joints;

insert into rejoin_sets (v, k, e)
   select osm_id, osm_id, extent from power_line where osm_id in (
      select unnest(line_id) from redundant_joints
  );

/* 4th time is the charm */
do $$
declare
    p rejoin_pairs;
    s rejoin_sets;
    d rejoin_sets;
begin
    for p in select * from rejoin_pairs
    loop
        select * into s from rejoin_sets where v = p.src;
        select * into d from rejoin_sets where v = p.dst;
        if s.k != d.k
        then
            update rejoin_sets set k = s.k where k = d.k;
            update rejoin_sets set e = connect_lines(s.e, d.e),
                                   t = reuse_terminals(s.t, d.t)
                where k = s.k;
        end if;
    end loop;
end
$$ language plpgsql;

insert into rejoin_lines (synth_id, source_id, extent, terminals)
    select concat('r', nextval('synthetic_objects')),
           array_agg(v), e, t
           from rejoin_sets group by k, e, t;

insert into power_line (osm_id, power_name, objects, extent, terminals)
    select synth_id, 'merge', source_line_objects(source_id), extent, terminals
           from rejoin_lines;

delete from power_line where osm_id in (select unnest(source_id) from rejoin_lines);
commit;
