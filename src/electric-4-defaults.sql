begin;
-- assign default values
-- TODO move this to after the merging steps
update electric_tags e
  set frequency = array[50.0]
  where voltage is not null and frequency is null;

update electric_tags e
  set cables = array[3]
  from line_osm_names l
  where l.osm_name = e.osm_name
    and voltage is not null and cables is null
    and not (0.0 = all(frequency));

update electric_tags e
  set wires = array[r.wires]
  from reference_parameters r
  where exists (
      select 1 from line_osm_names l where l.osm_name = e.osm_name
   )
   and e.wires is null and e.voltage is not null
   and r.voltage = any(e.voltage);

update electric_tags e
  set wires = array[1]
  from line_osm_names l
  where l.osm_name = e.osm_name
    and voltage is not null and wires is null;
commit;
