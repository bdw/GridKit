#!/bin/bash
SCIGRID_HOME=$HOME/Code/scigrid
DATABASE_NAME=france
OSM_DATAFILE=$HOME/Data/france-power.o5m
dropdb --if-exists $DATABASE_NAME || exit 1
createdb $DATABASE_NAME || exit 1
psql -d $DATABASE_NAME -c 'CREATE EXTENSION postgis;' || exit 1
psql -d $DATABASE_NAME -c 'CREATE EXTENSION hstore;' || exit 1

osm2pgsql -d $DATABASE_NAME -c -k -s \
	-S $SCIGRID_HOME/data/02_osm_raw_power_data/power.style \
	$OSM_DATAFILE  || exit 1

time psql -d $DATABASE_NAME -f ./prepare-tables.sql

