#!/bin/bash

# run postgresql with 'safe mode'
shopt -s expand_aliases
alias psql='psql -v ON_ERROR_STOP=1'

psql -f src/step-1-merge-stations.sql || exit 1
psql -f src/step-2-eliminate-internal-lines.sql || exit 1
psql -f src/step-3-split-lines-passing-stations.sql || exit 1
psql -f src/step-4-insert-attachment-points.sql || exit 1
psql -f src/step-5a-line-terminal-intersections.sql || exit 1
psql -f src/step-5b-mutual-terminal-intersections.sql || exit 1
psql -f src/step-5c-line-join-stations.sql
psql -f src/step-6-merge-lines.sql
