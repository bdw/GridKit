begin;
drop sequence if exists network_bus_id;
drop table if exists station_transformer;
drop table if exists external_converter_terminal;
drop table if exists station_terminal;

drop table if exists network_line;
drop table if exists network_converter;
drop table if exists network_link;
drop table if exists network_transformer;
drop table if exists network_generator;
drop table if exists network_bus;

-- split stations into buses
-- insert transformers
-- export to text format
create table station_terminal (
    station_id     integer not null,
    voltage        integer null,
    dc             boolean not null,
    converter      boolean not null,
    network_bus_id integer primary key
);

create table external_converter_terminal (
    terminal_id    integer primary key,
    terminal_location geometry(point,3857),
    station_id     integer not null,
    network_bus_id         integer references station_terminal (network_bus_id),
    connection_line geometry(linestring,3857)
);

create index station_terminal_idx on station_terminal (station_id, voltage, dc);

create table station_transformer (
    transformer_id integer primary key,
    station_id     integer,
    src_bus_id     integer references station_terminal (network_bus_id),
    dst_bus_id     integer references station_terminal (network_bus_id),
    src_voltage    integer,
    dst_voltage    integer,
    src_dc         boolean,
    dst_dc         boolean
);

create sequence network_bus_id;

with connected_line_structures as (
    select distinct
           station_id, voltage, dc_line,
           n.topology_name in ('Converter Station',
                               'Converter Station Back-to-back') as converter
      from topology_nodes n
      join line_structure l on l.line_id = any(n.line_id)
     order by station_id, voltage
)
insert into station_terminal (station_id, voltage, dc, converter, network_bus_id)
     select station_id, voltage, dc_line, converter, nextval('network_bus_id')
       from connected_line_structures;

insert into external_converter_terminal (terminal_id, terminal_location,
                                         station_id, network_bus_id, connection_line)
     select distinct on (t.station_id)
            s.station_id, n.station_location, t.station_id, t.network_bus_id,
            st_makeline(n.station_location, n.station_location)
       from station_terminal s
       join topology_nodes n on s.station_id = n.station_id
       join station_terminal t on s.station_id = t.station_id and s.network_bus_id <> t.network_bus_id
      where s.converter and s.dc
      order by t.station_id, t.voltage desc ;

with isolated_converter_terminal as (
     select s.station_id
       from station_terminal s
       join topology_nodes n on s.station_id = n.station_id
      where converter
      group by s.station_id
     having count(s.station_id) < 2
)
insert into external_converter_terminal (terminal_id, terminal_location,
                                         station_id, network_bus_id, connection_line)
     select distinct on (fs.station_id)
            t.station_id, t.station_location, f.station_id, fs.network_bus_id,
            st_makeline(f.station_location, t.station_location)
       from isolated_converter_terminal i
       join topology_nodes t on t.station_id = i.station_id
       join lateral (
            select station_id, station_location from topology_nodes n
             where n.station_id != t.station_id
                -- not to another HVDC station, or to a joint
               and n.topology_name not in (
               'joint',
               'Wind farm',
               'Converter Station',
               'Converter Station Back-to-back'
               )
             -- indexed k-nearest neighbor
             order by t.station_location <-> n.station_location limit 1
             -- TODO, this distorts lengths due to projection; maybe
             -- better results with geography measurements
            ) f on st_distance(t.station_location, f.station_location) < :hvdc_distance
       join station_terminal fs on fs.station_id = f.station_id
      order by fs.station_id, fs.voltage desc ;

-- exported entities
create table network_bus (
    bus_id      integer primary key,
    station_id  integer,
    voltage     integer,
    dc          boolean,
    symbol      text,
    under_construction boolean,
    tags        hstore,
    x           numeric,
    y           numeric
    -- geometry    geometry(Point,4326)
);

create table network_link (
    link_id    integer primary key,
    bus0       integer references network_bus (bus_id),
    bus1       integer references network_bus (bus_id),
    "length"   numeric,
    underground boolean not null,
    under_construction boolean not null,
    tags       hstore,
    geometry   text
    -- geometry   geometry(LineString, 4326)
);

create table network_line (
    line_id      integer primary key,
    bus0         integer references network_bus (bus_id),
    bus1         integer references network_bus (bus_id),
    voltage      integer,
    circuits     integer not null,
    "length"     numeric,
    underground  boolean not null,
    under_construction boolean not null,
    tags         hstore,
    geometry     text
    -- geometry     geometry(LineString, 4326)
);

create table network_generator (
    generator_id integer primary key,
    bus_id       integer not null references network_bus(bus_id),
    technology   text,
    capacity     numeric,
    tags         hstore
    -- geometry     geometry(Point, 4326)
);

create table network_converter (
    converter_id integer primary key,
    bus0         integer not null references network_bus(bus_id),
    bus1         integer not null references network_bus(bus_id)
    -- geometry     geometry(Point, 4326)
);

create table network_transformer (
    transformer_id integer primary key,
    bus0           integer references network_bus(bus_id),
    bus1           integer references network_bus(bus_id)
    -- geometry       geometry(Point, 4326)
);

insert into network_bus (bus_id, station_id, voltage, dc, symbol, under_construction, tags, x, y)
     select t.network_bus_id, t.station_id, t.voltage, t.dc, n.topology_name, p.under_construction,
            p.tags,
            st_x(st_transform(n.station_location, 4326)),
            st_y(st_transform(n.station_location, 4326))
       from topology_nodes n
       join station_terminal t on t.station_id = n.station_id
  left join station_properties p on p.station_id = n.station_id
  left join external_converter_terminal e on e.terminal_id = t.station_id
      where e.terminal_id is null or not t.dc or n.topology_name = 'Converter Station Back-to-back';
      -- buses for which external converter terminals exist are skipped

-- DC lines connect external terminals directly
insert into network_link (link_id, bus0, bus1, underground, under_construction,
                          "length", tags, geometry)
     select e.line_id,
            coalesce(se.network_bus_id, s.network_bus_id),
            coalesce(de.network_bus_id, d.network_bus_id),
            l.underground, l.under_construction,
            st_length(st_transform(e.line_extent, 4326)::geography),
            l.tags, st_astext(st_transform(e.line_extent, 4326))
       from topology_edges e
       join line_structure l   on l.line_id = e.line_id
       join station_terminal s on s.station_id = e.station_id[1] and s.dc
  left join external_converter_terminal se on se.terminal_id = s.station_id
       join station_terminal d on d.station_id = e.station_id[2] and d.dc
  left join external_converter_terminal de on de.terminal_id = d.station_id
      where l.dc_line;

-- Back-to-back Converters appear as separate converters
insert into network_converter (converter_id, bus0, bus1)
     select distinct
            s.station_id, s.network_bus_id, coalesce(d.network_bus_id, de.network_bus_id)
            -- st_astext(st_transform(n.station_location, 4326))
       from station_terminal s
  left join station_terminal d on s.station_id = d.station_id and s.network_bus_id < d.network_bus_id
  left join external_converter_terminal de on de.terminal_id = s.station_id
       join topology_nodes n on s.station_id = n.station_id
      where s.converter
        and n.topology_name = 'Converter Station Back-to-back'
        and coalesce(d.station_id, de.terminal_id) is not null;

-- AC lines
insert into network_line (line_id, bus0, bus1, voltage, circuits,
                          underground, under_construction, "length", tags, geometry)
     select e.line_id, s.network_bus_id, d.network_bus_id,
            l.voltage, l.circuits, l.underground, l.under_construction,
            st_length(st_transform(e.line_extent, 4326)::geography), l.tags,
            st_astext(st_transform(e.line_extent, 4326))
       from topology_edges e
       join line_structure l   on l.line_id = e.line_id
       join station_terminal s on s.station_id = e.station_id[1]
        and s.voltage = l.voltage and not s.dc
       join station_terminal d on d.station_id = e.station_id[2]
        and d.voltage = l.voltage and not d.dc
      where not l.dc_line;

-- Transformers
insert into network_transformer (transformer_id, bus0, bus1)
     select nextval('line_id'),
            s.network_bus_id, d.network_bus_id
            -- st_astext(st_transform(n.station_location, 4326))
       from station_terminal s
       join station_terminal d on s.station_id = d.station_id and s.network_bus_id < d.network_bus_id
       join topology_nodes n on s.station_id = n.station_id
      where not s.dc and not d.dc and n.topology_name != 'joint';

-- Generators
-- insert into network_generator (generator_id, bus_id, technology, capacity, tags, geometry)
--      select g.generator_id,
--             (select network_bus_id from station_terminal t
--               where g.station_id = t.station_id order by voltage asc limit 1),
--             p.tags->'symbol', (p.tags->'mw')::numeric, p.tags - array['symbol','mw'],
--             st_transform(p.location, 4326)
--        from topology_generators g
--        join power_generator p on p.generator_id = g.generator_id;



commit;
