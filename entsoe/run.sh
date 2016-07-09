#!/bin/bash


psql -f ../src/prepare-functions.sql
psql -f gridkit-start.sql
psql -f ../src/spatial-1-merge-stations.sql
psql -f ../src/spatial-2-eliminate-line-overlap.sql
psql -f ../src/spatial-3-attachment-joints.sql
psql -f ../src/spatial-4-terminal-intersections.sql
psql -f ../src/spatial-5-terminal-joints.sql
psql -f ../src/spatial-6-merge-lines.sql
psql -f ../src/topology-1-connections.sql
psql -f electric-properties.sql
psql -f abstraction.sql

bash ./export.sh
echo "All done"
