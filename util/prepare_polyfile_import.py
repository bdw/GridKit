#!/usr/bin/env python
from __future__ import print_function, unicode_literals, division
import sys
import os
import io
from polyfile import PolyfileParser
from geometry import Polygon

polygons = dict()
parser = PolyfileParser()
for file_name in sys.argv[1:]:
    if not os.path.isfile(file_name):
        print("Usage: {0} <files>".format(sys.argv[0]))
    name, ext = os.path.splitext(os.path.basename(file_name))
    try:
        pr = parser.parse(io.open(file_name, 'r').read())
        pl = Polygon(pr[1]['1'])
        polygons[name] = pl.to_wkt()
    except Exception as e:
        print("Could not process {0} because {1}".format(file_name, e))
        quit(1)



with io.open('import-polygons.sql', 'w') as handle:
    handle.write('''
CREATE TABLE IF NOT EXISTS polygons (
    name varchar(64) primary key,
    polygon geometry(polygon, 4326)
);
INSERT INTO polygons (name, polygon) VALUES {0};
'''.format(','.join("('{0}', ST_SetSRID(ST_GeomFromText('{1}'), 4326))".format(n, p) for (n, p) in polygons.items())))
# of course you can abuse this. don't do that, then
