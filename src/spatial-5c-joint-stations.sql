begin;
drop table if exists line_joints;
create table line_joints (
    synth_id    varchar(64),
    objects     varchar(64) array,
    terminal_id int[],
    area        geometry(polygon, 3857)
);

insert into line_joints (synth_id, terminal_id, area, objects)
    select concat('j', nextval('synthetic_objects')),
           array_agg(s.v) as terminal_id, st_union(t.area),
           array_agg(t.osm_id)
       from terminal_sets s
       join line_terminals t on t.id = s.v
       join power_line l on l.osm_id = t.osm_id
       group by s.k having count(*) > 2;

insert into power_station (osm_id, power_name, location, area)
    select synth_id, 'joint', st_centroid(area), area
        from line_joints;

insert into osm_objects (osm_id, objects)
    select synth_id, source_objects(objects) from line_joints;

update power_line l
   set terminals = minimal_terminals(l.extent, j.area, l.terminals)
         from line_joints j where l.osm_id = any(j.objects);


delete from terminal_intersections where id in (
    select id from terminal_intersections i
              join line_joints j on i.src = any(j.terminal_id) or i.dst = any(j.terminal_id)
);
delete from line_terminals where id in (
    select unnest(terminal_id) from line_joints
);

commit;
