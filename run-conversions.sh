#!/bin/bash

# run postgresql with 'safe mode'
shopt -s expand_aliases
alias psql='psql -v ON_ERROR_STOP=1'

# shared node algorithms before any others
psql -f src/node-1-find-shared.sql || exit 1
psql -f src/node-2-merge-lines.sql || exit 1
psql -f src/node-3-line-joints.sql || exit 1

# spatial algorithms benefit from reduction of work from shared node
# algorithms
psql -f src/spatial-1-merge-stations.sql || exit 1
psql -f src/spatial-2-eliminate-internal-lines.sql || exit 1
psql -f src/spatial-3-eliminate-line-overlap.sql || exit 1
psql -f src/spatial-4-attachment-joints.sql || exit 1
psql -f src/spatial-5a-line-terminal-intersections.sql || exit 1
psql -f src/spatial-5b-mutual-terminal-intersections.sql || exit 1
psql -f src/spatial-5c-joint-stations.sql || exit 1
psql -f src/spatial-6-merge-lines.sql || exit 1
