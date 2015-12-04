#!/bin/bash
SCIGRID_HOME=$HOME/Code/scigrid
DATABASE_NAME=germany
dropdb --if-exists $DATABASE_NAME || exit 1
createdb $DATABASE_NAME || exit 1
psql -d $DATABASE_NAME -c 'CREATE EXTENSION postgis;' || exit 1
psql -d $DATABASE_NAME -c 'CREATE EXTENSION hstore;' || exit 1

osm2pgsql -d $DATABASE_NAME -c -k -s \
	-S $SCIGRID_HOME/data/02_osm_raw_power_data/power.style \
	 $SCIGRID_HOME/data/02_osm_raw_power_data/de_power_151109.osm.pbf \
	 || exit 1

time psql -d $DATABASE_NAME -f ./restructure-tables.sql

