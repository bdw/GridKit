begin;
drop table if exists reference_line_parameters;
drop table if exists line_impedances;
create table reference_line_parameters (
    voltage integer primary key,
    r_ohmkm numeric,
    x_ohmkm numeric,
    c_nfkm numeric, -- nano-farad
    i_th_max_a numeric -- ampere
);
insert into reference_line_parameters (voltage, r_ohmkm, x_ohmkm, c_nfkm, i_th_max_a)
    values (132, null,null,null,null);

create table line_impedances (
    line_id integer primary key,
    line_length numeric,  
    r_ohm_km numeric,
    x_ohm_km numeric,
    c_nfkm numeric,
    i_th_max_a numeric
);

commit;
