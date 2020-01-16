#!/bin/bash
psql -c "COPY network_bus TO STDOUT WITH CSV HEADER QUOTE ''''" > result/buses.csv
psql -c "COPY network_line TO STDOUT WITH CSV HEADER QUOTE ''''" > result/lines.csv
psql -c "COPY network_link TO STDOUT WITH CSV HEADER QUOTE ''''" > result/links.csv
psql -c "COPY network_converter TO STDOUT WITH CSV HEADER QUOTE ''''" > result/converters.csv
psql -c "COPY network_transformer TO STDOUT WITH CSV HEADER QUOTE ''''" > result/transformers.csv
psql -c "COPY network_generator TO STDOUT WITH CSV HEADER QUOTE ''''" > result/generators.csv
