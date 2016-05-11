begin;
delete from features where import_id in (
    select greatest(a.import_id, b.import_id) from features a, features b
        where a.import_id != b.import_id and a.properties = b.properties and a.geometry = b.geometry
);
insert into features (feature_id, geometry, properties)
   select feature_id, (st_dump(geometry)).geom, properties from features
       where st_geometrytype(geometry) = 'ST_MultiLineString';
delete from features where st_geometrytype(geometry) = 'ST_MultiLineString';
commit;
