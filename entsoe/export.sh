#!/bin/bash
psql -c "COPY network_bus TO STDOUT WITH CSV HEADER QUOTE ''''" > buses.csv
psql -c "COPY network_line TO STDOUT WITH CSV HEADER QUOTE ''''" > lines.csv
psql -c "COPY network_link TO STDOUT WITH CSV HEADER QUOTE ''''" > links.csv
psql -c "COPY network_converter TO STDOUT WITH CSV HEADER QUOTE ''''" > converters.csv
psql -c "COPY network_transformer TO STDOUT WITH CSV HEADER QUOTE ''''" > transformers.csv
psql -c "COPY network_generator TO STDOUT WITH CSV HEADER QUOTE ''''" > generators.csv

zip entsoe.zip README.md buses.csv lines.csv links.csv converters.csv transformers.csv generators.csv
