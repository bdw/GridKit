begin;

insert into electrical_properties (osm_id, frequency, voltage, conductor_bundles, subconductors, power_name, operator, name)
    select osm_id, string_to_array(tags->'frequency', ';')::float[], string_to_array(tags->'voltage', ';')::int[],
        string_to_array(tags->'cables', ';')::int[], string_to_array(tags->'wires', ';'),
        tags->'power', tags->'operator', tags->'name'
        from power_line;

insert into electrical_properties (osm_id, frequency, voltage, power_name, operator, name)
    select osm_id, string_to_array(tags->'frequency', ';')::float[], string_to_array(tags->'voltage', ';')::int[],
        tags->'power', tags->'operator', tags->'name' from power_station where power_name != 'joint';

/* joints are more like lines. */
insert into electrical_properties (osm_id, frequency, voltage, conductor_bundles, subconductors, power_name, operator, name)
    select osm_id, string_to_array(tags->'frequency', ';')::float[], string_to_array(tags->'voltage', ';')::int[],
        string_to_array(tags->'cables', ';')::int[], string_to_array(tags->'wires', ';'),
        tags->'power', tags->'operator', tags->'name'
        from power_station where power_name = 'joint';

commit;
