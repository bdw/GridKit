-- to ensure that we don't accidentally create crossings, minimise the
-- terminals of lines that are attached to attachment points
begin;
do $$
declare
    line           record;
    start_terminal geometry;
    end_terminal   geometry;
    start_area     geometry(polygon);
    end_area       geometry(polygon);
    terminal_union geometry;
begin
    for line in select osm_id, extent, terminals from power_line where osm_id in (
        select synth_id from attachment_split_lines union all select unnest(attach_id) from line_attachments
    )
    loop

        start_terminal = st_buffer(st_startpoint(line.extent), 100);
        end_terminal   = st_buffer(st_endpoint(line.extent), 100);

        -- limit startpoint terminal if connected with an attachment point
        start_area = area from power_station
             where st_intersects(area, start_terminal) and power_name = 'attachment'
             order by st_distance(area, st_startpoint(line.extent)) limit 1;
        if start_area is not null
        then
             start_terminal = case when st_intersects(start_area, st_startpoint(line.extent))
                                   then st_buffer(st_startpoint(line.extent), 1)
                                   else st_buffer(st_shortestline(start_area, st_startpoint(line.extent)), 1) end;
        end if;


        -- same for endpoints
        end_area = area from power_station
             where st_intersects(area, end_terminal) and power_name = 'attachment'
             order by st_distance(area, st_endpoint(line.extent)) limit 1;

        if end_area is not null
        then
             end_terminal = case when st_intersects(end_area, st_endpoint(line.extent))
                                 then st_buffer(st_endpoint(line.extent), 1)
                                 else st_buffer(st_shortestline(end_area, st_endpoint(line.extent)), 1) end;
        end if;

        terminal_union = st_union(start_terminal, end_terminal);

        if not st_contains(terminal_union, line.terminals)
        then
            update power_line set terminals = terminal_union where osm_id = line.osm_id;
        end if;
    end loop;
end
$$ language plpgsql;

commit;
