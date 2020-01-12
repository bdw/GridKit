import fiona
import numpy as np
import pandas as pd
import geopandas as gpd
import geojson
from shapely.geometry import Point, LineString

from six import iteritems
from six.moves import reduce
from itertools import chain, count, permutations
import os, sys

type_map = dict(MultiLineString="LineString",
                LineString="LineString",
                Point="Point")


def sort_features(fn, features):
    with open(fn) as fp:
        t = geojson.load(fp)

    offset = {t: fs[-1]['id']+1 for t, fs in iteritems(features)}

    for n, f in enumerate(t['features']):
        t = type_map[f['geometry']['type']]
        f['id'] = offset.setdefault(t, 0) + n

        features.setdefault(t, []).append(f)

    return features


def trim_fixedid(name):
    return name[:-len('-fixedid')] if name.endswith('-fixedid') else name


def gen_outfn(fn, suffix, tmpdir=None):
    name, ext = os.path.splitext(os.path.basename(fn))
    outfn = trim_fixedid(name) + suffix + ext

    if tmpdir is not None:
        outfn = os.path.join(tmpdir, outfn)
    else:
        outfn = os.path.join(os.path.dirname(fn), outfn)

    if os.path.exists(outfn):
        os.unlink(outfn)

    return outfn


def stitch_tiles(fn):
    df = gpd.read_file(fn)
    df = df.rename(columns={'OBJECTID': 'oid',
                            'ogc_fid': 'oid',
                            'underconstruction': 'under_construction',
                            'UnderConst': 'under_construction',
                            'Symbol': 'symbol',
                            'ABR': 'country',
                            'VoltageLev': 'voltagelevel',
                            'T9_Code': 't9_code',
                            'Visible': 'visible',
                            'Current_': 'current',
                            'NumberOfCi': 'numberofcircuits',
                            'Undergroun': 'underground',
                            'Tie_line': 'tie_line',
                            'Text_': 'text_',
                            'LengthKm': 'shape_length'})
    df['tie_line'] = df['tie_line'].fillna(0.).astype(int)
    for f in ('visible', 'underground', 'under_construction'):
        df[f] = df[f].astype(int)
    df['numberofcircuits'] = df['numberofcircuits'].astype(int)
    df['shape_length'] = df['shape_length'].astype(float)
    df['symbol'] = df['symbol'].str.split(',').str[0]
    uc_b = df['symbol'].str.endswith(' Under Construction')
    df.loc[uc_b, 'symbol'] = df.loc[uc_b, 'symbol'].str[:-len(' Under Construction')]

    # Break MultiLineStrings
    e = (df.loc[df.type == 'MultiLineString', 'geometry'])
    if not e.empty:
        extra = df.drop("geometry", axis=1).join(
            pd.Series(chain(*e), np.repeat(e.index, e.map(len)), name="geometry"),
            how="right"
        )
        df = df[df.type != 'MultiLineString'].append(extra, ignore_index=True)

    def up_to_point(l, p, other):
        if l.boundary[1].distance(other) > l.boundary[0].distance(other):
            l = LineString(l.coords[::-1])
        for n, r in enumerate(l.coords):
            if l.project(Point(r)) > l.project(p):
                return l.coords[:n]
        return l.coords[:]

    def stitch_lines(a, b):
        if a.buffer(1e-2).contains(b):
            return a
        p = a.intersection(b)
        if p.is_empty:
            d = a.distance(b)/(2-1e-2)
            assert d < .5e-2
            p = a.buffer(d).intersection(b.buffer(d)).centroid
        p = p.representative_point()
        return LineString(up_to_point(a, p, b) + up_to_point(b, p, a)[::-1])

    def unique_lines(df):
        dfbuf = df.buffer(1e-2)
        for i, geom in df.geometry.iteritems():
            ndfbuf = dfbuf.drop(i)
            if ndfbuf.contains(geom).any():
                dfbuf = ndfbuf
        return df.loc[dfbuf.index]

    def stitch_where_possible(df):
        if len(df) == 1: return df.geometry.iloc[0]

        df = unique_lines(df)

        for p in permutations(df.geometry.iloc[1:]):
            try:
                #print("Stitching {}: {} lines".format(df.ogc_fid.iloc[0], len(df)))
                return reduce(stitch_lines, p, df.geometry.iloc[0])
            except AssertionError:
                pass
        else:
            raise Exception("Could not stitch lines with `oid = {}`".format(df.oid.iloc[0]))

    stitched = df.groupby('oid').apply(stitch_where_possible)
    df = gpd.GeoDataFrame(df.groupby('oid').first().assign(geometry=stitched)).reset_index()

    outfn = gen_outfn(fn, '-fixed')
    df.set_index('oid', drop=False).to_file(outfn, driver='GeoJSON')
    return outfn

def strip_duplicate_stations(fn):
    with open(fn) as fp:
        f = geojson.load(fp)

    key_map = {'OBJECTID': 'oid',
                'ogc_fid': 'oid',
                'Under_cons': 'under_construction',
                'name_all': 'name',
                'Name_Eng': 'name',
                'Symbol': 'symbol',
                'Country': 'country',
                'Tie_line_s': 'tie_line_s',
                'Visible': 'visible',
                'MW': 'capacity',
                'mw': 'capacity'}
    seen_oids = set()
    features = []

    for feature in f['features']:
        prop = feature['properties']
        for old, new in key_map.items():
            if old in prop:
                prop[new] = prop.pop(old)

        feature['id'] = oid = prop['oid']
        if oid in seen_oids:
            continue
        seen_oids.add(oid)

        if 'symbol' in prop:
            prop['symbol'] = prop['symbol'].split(',', 1)[0]

        if 'TSO' in prop:
            prop['TSO'] = prop['TSO'].strip()

        if 'EIC_code' in prop:
            prop['EIC_code'] = prop['EIC_code'].strip()

        features.append(feature)

    f['features'] = features

    outfn = gen_outfn(fn, '-fixed')
    with open(outfn, 'w') as fp:
        geojson.dump(f, fp)
    return outfn

if __name__ == '__main__':
    base = sys.argv[1]
    files = sys.argv[2:]

    features = dict()
    for fn in files:
        sort_features(fn, features)

    for geom_type, fs in iteritems(features):
        fixed_id_fn = gen_outfn(base + '.geojson', '-{}-fixedid'.format(geom_type))
        with open(fixed_id_fn, 'w') as fp:
            geojson.dump({'type': 'FeatureCollection', 'features': fs}, fp)

        if geom_type == 'LineString':
            fixed_fn = stitch_tiles(fixed_id_fn)
            print("Stitched tiles into {}.".format(fixed_fn))
        elif geom_type == 'Point':
            fixed_fn = strip_duplicate_stations(fixed_id_fn)
            print("Stripped station duplicates into {}.".format(fixed_fn))
        else:
            print("Incompatible geometry type {} in {}.".format(geom_type, fixed_id_fn))
