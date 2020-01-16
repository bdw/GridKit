#!/bin/bash

BASE=$(realpath $PWD/..)
PGUSER=postgres
PGPASSWORD=mysecretpassword

echo
echo "Download geojson from mapbox"
echo "============================"
docker run -it -v $BASE:/app:rw -w /app/entsoe node:8.16.0-alpine sh download.sh

echo
echo "Start postgis database server"
echo "============================="
docker run --name gridkit-postgis -e POSTGRES_PASSWORD=$PGPASSWORD -d mdillon/postgis

echo
echo "Import into postgis"
echo "==================="
docker run -it --link gridkit-postgis:postgres --rm \
    -v $BASE:/app:rw -w /app/entsoe \
    -e PGUSER=$PGUSER -e PGPASSWORD=$PGPASSWORD \
    python:2 \
    bash -c 'pip install -r requirements.txt && env PGHOST="$POSTGRES_PORT_5432_TCP_ADDR" PGPORT="$POSTGRES_PORT_5432_TCP_PORT" ./import.sh'

echo
echo "Run Gridkit and export into result directory"
echo "============================================"
docker run -it --link gridkit-postgis:postgres --rm \
    -v $BASE:/app:rw -w /app/entsoe \
    -e PGUSER=$PGUSER -e PGPASSWORD=$PGPASSWORD \
    mdillon/postgis \
    bash -c 'env PGHOST="$POSTGRES_PORT_5432_TCP_ADDR" PGPORT="$POSTGRES_PORT_5432_TCP_PORT" ./run.sh'

echo
echo "Tear down postgis server"
echo "========================"
docker stop gridkit-postgis
docker rm gridkit-postgis