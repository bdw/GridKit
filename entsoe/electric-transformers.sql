begin;
drop table if exists transformers;
create table transformers (
    transformer_id integer primary key,
    station_id integer not null,
    high_voltage integer,
    low_voltage integer,
    location geometry(point,3857)
);
with connected_voltages(station_id, voltage) as (
    select station_id, voltage from topology_nodes n join computed_line_properties l on l.line_id = any(n.line_id)
), voltage_combinations (station_id, high_voltage, low_voltage) as (
   select distinct _a.station_id, greatest(_a.voltage, _b.voltage), least(_a.voltage, _b.voltage)
     from connected_voltages _a, connected_voltages _b
    where _a.station_id = _b.station_id
      and _a.voltage != _b.voltage
)
insert into transformers (transformer_id, station_id, high_voltage, low_voltage, location)
   select nextval('line_id'), c.station_id, c.high_voltage, c.low_voltage, n.station_location
     from voltage_combinations c
     join topology_nodes n on n.station_id = c.station_id;

commit;
