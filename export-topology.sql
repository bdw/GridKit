-- v_id,lon,lat,typ,voltage,frequency,name,operator,ref,wkt_srid_4326
copy (
     select v_id, lon, lat, typ, voltage, frequency, name, operator, ref, wkt_srid_4326
            from heuristic_vertices
) to '/tmp/heuristic_vertices.csv' with csv header quote '''';

-- l_id,v_id_1,v_id_2,voltage,cables,wires,frequency,name,operator,ref,length_m,r_ohmkm,x_ohmkm,c_nfkm,i_th_max_a,from_relation,wkt_srid_4326
copy (
     select l_id, v_id_1, v_id_2, voltage, cables, wires, frequency, name, operator, ref, length_m, r_ohmkm, x_ohmkm, c_nfkm, i_th_max_a, from_relation, wkt_srid_4326
            from heuristic_links
) to '/tmp/heuristic_links.csv' with csv header quote '''';

-- v_id,lon,lat,typ,voltage,frequency,name,operator,ref,wkt_srid_4326
copy (
     select v_id, lon, lat, typ, voltage, frequency, name, operator, ref, wkt_srid_4326
            from heuristic_vertices_highvoltage
) to '/tmp/highvoltage_vertices.csv' with csv header quote '''';

-- l_id,v_id_1,v_id_2,voltage,cables,wires,frequency,name,operator,ref,length_m,r_ohmkm,x_ohmkm,c_nfkm,i_th_max_a,from_relation,wkt_srid_4326
copy (
     select l_id, v_id_1, v_id_2, voltage, cables, wires, frequency, name, operator, ref, length_m, r_ohmkm, x_ohmkm, c_nfkm, i_th_max_a, from_relation, wkt_srid_4326
            from heuristic_links_highvoltage
) to '/tmp/highvoltage_links.csv' with csv header quote '''';
