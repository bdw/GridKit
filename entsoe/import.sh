#!/bin/bash

BASE=${1-entsoe}
ZOOM=${2-6}

python fixup-mapbox-tiles.py data/${BASE} data/${BASE}*-z${ZOOM}.geojson
python ../util/geojson-to-postgis.py data/${BASE}-*-fixed.geojson
