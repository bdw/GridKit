#!/bin/bash

BASE=${1-rusty}
ZOOM=${2-6}

python ../util/geojson-to-postgis.py ${BASE}-*-fixed.geojson
