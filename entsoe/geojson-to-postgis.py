#!/usr/bin/env python
from __future__ import print_function, unicode_literals
import operator
import psycopg2
import psycopg2.extras
import io
import json
import sys
import logging


CREATE_TABLES = '''
CREATE EXTENSION IF NOT EXISTS hstore;
CREATE EXTENSION IF NOT EXISTS postgis;
DROP TABLE IF EXISTS features;
CREATE TABLE features (
    import_id serial,
    feature_id integer not null,
    geometry  geometry(geometry,4326),
    properties hstore
);
'''

INSERT_STATEMENT = 'INSERT INTO features (feature_id, geometry, properties) VALUES (%s, ST_SetSRID(ST_GeomFromText(%s), 4326), %s);'

def hstore(d):
    return dict((unicode(k), unicode(v)) for k, v, in d.items())

def wkt(g):
    def coords(c):
        if isinstance(c[0], list):
            if isinstance(c[0][0], list):
                f = '({0})'
            else:
                f = '{0}'
            t = ', '.join(f.format(a) for a in map(coords, c))
        else:
            t = '{0:f} {1:f}'.format(*c)
        return t
    return '{0:s} ({1:s})'.format(g['type'].upper(), coords(g['coordinates']))


def import_feature(cur,feature_data):
    if feature_data.get('type') == 'FeatureCollection':
        for feature in feature_data['features']:
            import_feature(cur, feature)
    elif feature_data.get('type') == 'Feature':
        cur.execute(INSERT_STATEMENT,
                    (feature_data['id'],
                     wkt(feature_data['geometry']),
                     hstore(feature_data['properties'])))

if __name__ == '__main__':
    logging.basicConfig(level=logging.DEBUG)
    con = psycopg2.connect('')
    # create table
    with con:
        with con.cursor() as cur:
            cur.execute(CREATE_TABLES)

    # use hstore to store attributes
    psycopg2.extras.register_hstore(con)


    if len(sys.argv) == 1:
        handles = [sys.stdin]
    else:
        handles = [io.open(a,'r') for a in sys.argv[1:]]
    for handle in handles:
        with handle:
            feature_data = json.load(handle)
        with con:
            with con.cursor() as cur:
                import_feature(cur, feature_data)
            con.commit()
