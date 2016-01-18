#!/bin/bash

psql -f src/step-1-merge-stations.sql
psql -f src/step-2-eliminate-internal-lines.sql
psql -f src/step-3-split-lines-passing-stations.sql
psql -f src/step-4-insert-attachment-points.sql
psql -f src/step-5a-line-terminal-intersections.sql
psql -f src/step-5b-mutual-terminal-intersections.sql
psql -f src/step-5c-line-join-stations.sql
psql -f src/step-6-merge-lines.sql
