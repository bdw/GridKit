begin;
drop table if exists line_joints;
create table line_joints (
    synth_id    varchar(64),
    objects     varchar(64) array,
    terminal_id int[],
    area        geometry(polygon, 3857)
);

with grouped_terminals(terminal_id) as (
	select array_agg(s.v)
		from terminal_sets s
		group by s.k having count(*) > 2
) insert into line_joints (synth_id, terminal_id, objects, area)
    select concat('j', nextval('synthetic_objects')), terminal_id,
           array(select osm_id from line_terminals where id = any(terminal_id)),
           (select st_union(area) from line_terminals where id = any(terminal_id))
        from grouped_terminals;


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
