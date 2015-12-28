begin transaction;

alter table power_line drop column if exists terminals;
alter table power_line drop colunn if exists text[];
alter table power_line add column source_objects text[];
alter table power_line add column terminals geometry;
alter table power_station drop column if exists area;
alter table power_station add column source_objects text[];
alter table power_station add column area geometry(polygon);


update power_line set terminals = ST_Buffer(ST_Union(ST_StartPoint(extent), ST_EndPoint(extent)), 100) where not ST_IsClosed(extent);
update power_station set area = case when st_geometrytype(location) = 'point' then st_buffer(location, 300) else st_buffer(location, 150) end;

drop index if exists power_station_location;
drop index if exists power_line_extent;
create index power_station_location on power_station using gist(location);
create index power_line_extent on power_line using gist(extent);

drop index if exists power_line_terminals;
drop index if exists power_station_area;
create index power_line_terminals on power_line using gist(terminals);
create index power_station_area on power_station using gist(area);


commit;
