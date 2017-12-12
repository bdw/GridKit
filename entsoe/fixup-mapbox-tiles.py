import fiona
import pandas as pd
import geopandas as gpd
import geojson
from shapely.geometry import Point, LineString

from six import iteritems
from six.moves import reduce
from itertools import count, permutations
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
    for f in ('visible', 'underground', 'tie_line', 'under_construction'):
        df[f] = df[f].astype(int)
    df['numberofcircuits'] = df['numberofcircuits'].astype(int)
    df['shape_length'] = df['shape_length'].astype(float)
    df['symbol'] = df['symbol'].str.split(',').str[0]
    uc_b = df['symbol'].str.endswith(' Under Construction')
    df.loc[uc_b, 'symbol'] = df.loc[uc_b, 'symbol'].str[:-len(' Under Construction')]

    # Break MultiLineStrings
    extra = []
    for i in count():
        e = (df[df.type == 'MultiLineString']
            .assign(geometry=lambda df: df.geometry.str[i])
            .dropna(subset=['geometry']))
        if e.empty: break
        extra.append(e)
    df = df[df.type != 'MultiLineString'].append(pd.concat(extra), ignore_index=True)

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
        if a.boundary.intersects(b.boundary):
            return a if a.length > b.length else b
        p = a.intersection(b)
        if p.is_empty:
            d = a.distance(b)/(2-1e-2)
            assert d < 1e-3
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

    stitched = df.groupby('oid').apply(stitch_where_possible)
    df = gpd.GeoDataFrame(df.groupby('oid').first().assign(geometry=stitched)).reset_index()

    outfn = gen_outfn(fn, '-fixed')
    df.set_index('oid', drop=False).to_file(outfn, driver='GeoJSON')
    return outfn

def strip_duplicate_stations(fn):
    df = gpd.read_file(fn)
    df = df.rename(columns={'OBJECTID': 'oid',
                            'ogc_fid': 'oid',
                            'Under_cons': 'under_construction',
                            'name_all': 'name',
                            'Name_Eng': 'name',
                            'Symbol': 'symbol',
                            'Country': 'country',
                            'Tie_line_s': 'tie_line_s',
                            'Visible': 'visible',
                            'MW': 'capacity',
                            'mw': 'capacity'})

    outfn = gen_outfn(fn, '-fixed')
    (df[~df.duplicated(subset=['oid'], keep='first')]
     .set_index('oid', drop=False)
     .to_file(outfn, driver='GeoJSON'))
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
