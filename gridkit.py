#!/usr/bin/env python
"""
GridKit is a power grid extraction toolkit.

Usage:
    python gridkit.py path/to/data-file.osm --filter \\
         --poly path/to/area.poly \\
         --pg user=gridkit database=gridkit
"""

from __future__ import print_function, unicode_literals, division
import os, sys, io, argparse, logging, subprocess, functools
try:
    import psycopg2
except ImportError:
    psycopg2 = False
__author__ = 'Bart Wiegmans'


def which(program):
    '''Find executable for a given name by PATH, or None if no executable could be found'''
    if os.name == 'nt':
        return _nt_which(program)
    elif os.name == 'posix':
        return _posix_which(program)
    raise NotImplementedError(os.platform)

def _nt_which(program):
    PATH = os.environ['PATH'].split(os.pathsep)
    EXT  = os.environ['PATHEXT'].split(os.pathsep)
    name, ext = os.path.splitext(program)
    if ext in EXT:
        # program is specified as foo.exe, for example, in which case
        # we don't go looking for foo.exe.exe or foo.exe.bat
        for p in PATH:
            n = os.path.join(p, program)
            if os.path.isfile(n):
                return n
    else:
        for p in PATH:
            for e in EXT:
                n = os.path.join(p, program + e)
                if os.path.isfile(n):
                    return n
    return None

def _posix_which(program):
    PATH = os.environ['PATH'].split(os.pathsep)
    for p in PATH:
        n = os.path.join(p, program)
        if os.path.isfile(n) and os.access(n, os.X_OK):
            return n
    return None

class QueryError(Exception):
    def __init__(self, error, query):
        super(QueryError, self).__init__(error)
        self.query = query

def make_copy_query(subquery_or_stable):
    if subquery_or_table.lower().startswith('select'):
        query = 'COPY ({0}) TO STDOUT WITH CSV HEADER'
    else:
        query = 'COPY {0} TO STDOUT WITH CSV HEADER'
    return query.format(subquery_or_table)


class PsqlWrapper(object):
    "Wrap psql client executable under subprocess"
    def check_connection(self):
        try:
            self.do_query('SELECT 1')
        except QueryError as e:
            return False
        else:
            return True

    def update_params(self, params):
        for n,v in params.items():
            k = 'PG' + n.upper()
            os.environ[k] = v

    def do_query(self, query):
        try:
            subprocess.check_call([PSQL, '-v', 'ON_ERROR_STOP=1', '-c', query])
        except subprocess.SubprocessError as e:
            raise QueryError(e, query)
        except OSError as e:
            raise Exception(e)

    def do_queryfile(self, queryfile):
        try:
            subprocess.check_call([PSQL, '-v', 'ON_ERROR_STOP=1', '-f', queryfile])
        except subprocess.SubprocessError as e:
            raise QueryError(e, queryfile)
        except OSError as e:
            raise Exception(e)

    def do_getcsv(self, subquery_or_table):
        query = _make_copy_query(subquery_or_table)
        try:
            return subprocess.check_output([PSQL, '-v', 'ON_ERROR_STOP=1', '-c', query]).decode('utf-8')
        except subprocess.SubprocessError as e:
            raise QueryError(e, subquery_or_table)
        except OSError as e:
            raise Exception(e)


class Psycopg2Wrapper(object):
    "Wrap psycopg2 for consistency with psql-wrapper"
    def __init__(self):
        self._connection = None
        self._params     = dict()

    def update_connection(self, params):
        if self._connection is not None:
            # close existing connection
            if not self._connection.closed:
                self._connection.close()
            self._connection = None
        self._params.update(**params)

    def check_connection(self):
        try:
            if self._connection is None:
                self._connection = psycopg2.connect(**self.params)
        except psycopg2.Error as e:
            return False
        else:
            return True

    def do_query(self, query):
        try:
            with self._connection.cursor() as cursor:
                cursor.execute(query)
        except psycopg2.Error as e:
            raise QueryError(e, query)

    def do_queryfile(queryfile):
        with io.open(queryfile, 'r', encoding='utf-8') as handle:
            query = handle.read()
        try:
            with self._connection.cursor() as cursor:
                cursor.execute(query)
        except psycopg2.Error as e:
            raise QueryError(e, query)

    def do_getcsv(subquery_or_table):
        handle = io.StringIO()
        query  = _make_copy_query(subquery_or_table)
        try:
            with self._connection.cursor() as cursor:
                cursor.copy_expert(query, handle)
            return handle.getvalue()
        except psycopg2.Error as e:
            raise QueryError(e, query)




class PgWrapper(Psycopg2Wrapper if psycopg2 else PsqlWrapper):
    '''
Wrap interfaces of both psycopg2 and psql-under-subprocess
Which of these is actually implemented depends on the runtime
environment; psycopg2 is given preference, but psql is a fallback.
'''
    pass

def setup_database(pg_client, database_name):
    pass

def do_import(pg_client, database_params, osm_data_file):
    if 'password' in database_params:
        os.environ['PGPASS'] = database_params['password']

def do_conversion(pg_client, voltage_cutoff=220000):
    f = functools.partial(os.path.join, BASE_DIR, 'src')
    # shared node algorithms

    pg_client.do_queryfile(f('node-1-find-shared.sql'))
    pg_client.do_queryfile(f('node-2-merge-lines.sql'))
    pg_client.do_queryfile(f('node-3-line-joints.sql'))

    # spatial algorithms
    pg_client.do_queryfile(f('spatial-1-merge-stations.sql'))
    pg_client.do_queryfile(f('spatial-2-eliminate-internal-lines.sql'))
    pg_client.do_queryfile(f('spatial-3-eliminate-line-overlap.sql'))
    pg_client.do_queryfile(f('spatial-4-attachment-joints.sql'))
    pg_client.do_queryfile(f('spatial-5a-line-terminal-intersections.sql'))
    pg_client.do_queryfile(f('spatial-5b-mutual-terminal-intersections.sql'))
    pg_client.do_queryfile(f('spatial-5c-joint-stations.sql'))
    pg_client.do_queryfile(f('spatial-6-merge-lines.sql'))

    # topological algoritms
    pg_client.do_queryfile(f('topology-1-connections.sql'))
    pg_client.do_queryfile(f('topology-2a-dangling-joints.sql'))
    pg_client.do_queryfile(f('topology-2b-redundant-splits.sql'))
    pg_client.do_queryfile(f('topology-2c-redundant-joints.sql'))
    pg_client.do_queryfile(f('topology-3a-assign-tags.sql'))
    pg_client.do_queryfile(f('topology-3b-electrical-properties.sql'))

    with io.open(f('topology-4-high-voltage-network.sql'), 'r') as handle:
        query_text = handle.read().replace('220000', str(voltage_cutoff))
        pg_client.do_query(query_text)
    pg_client.do_queryfile(f('topology-4-high-voltage-network.sql'))
    pg_client.do_queryfile(f('topology-5-abstraction.sql'))


def export_network_csv(pg_client):
    pass


parse_pair = lambda s: tuple(s.split('=', 1))
if __name__ == '__main__':

    logging.basicConfig(format='%(levelname)s [%(asctime)s] / %(message)s', level=logging.INFO)

    PSQL       = which('psql')
    OSM2PGSQL  = which('osm2pgsql')
    OSMCONVERT = which('osmconvert')
    OSMFILTER  = which('osmfilter')
    OSMOSIS    = which('osmosis')
    BASE_DIR   = os.path.realpath(os.path.dirname(__file__))

    if not psycopg2 and PSQL is None:
        logging.error("Can't load psycopg2 or find psql executable")
        quit(1)


    _ap = argparse.ArgumentParser()
    # polygon filter files
    _ap.add_argument('--filter', action='store_true', help='Filter input file for power data (requires osmfilter)')
    _ap.add_argument('--poly',type=str,nargs='+', help='Polygon file(s) to limit the areas of the input file (requires osmconvert)')
    _ap.add_argument('--pg', type=parse_pair, default=[], nargs='+', help='Connection arguments to PostgreSQL, eg. --pg user=gridkit database=europe')
    _ap.add_argument('--psql', type=str, help='Location of psql binary', default=PSQL)
    _ap.add_argument('--osm2pgsql', type=str, help='Location of osm2pgsql binary', default=OSM2PGSQL)
    _ap.add_argument('--voltage', type=int, help='High-voltage cutoff level', default=220000)
    _ap.add_argument('osmfile')
    _args = _ap.parse_args()

    # i've added this for the scigrid folks
    PSQL      = _args.psql
    OSM2PGSQL = _args.osm2pgsql
    osmfile   = _args.osmfile

    if OSM2PGSQL is None or not (os.path.isfile(OSM2PGSQL) and os.access(OSM2PGSQL, os.X_OK)):
        logging.error("Cannot find osm2pgsql executable")
        quit(1)

    if _args.filter:
        if not OSMFILTER:
            logging.error("Cannot find osmfilter executable, necessary for --filter")
            quit(1)
        name, ext = os.path.splitext(osmfile)
        new_name  = name + '-power.o5m'
        logging.info("Filtering %s to make %s", osmfile, new_name)
        subprocess.check_call([OSMFILTER, osmfile, '--keep="power=*"', '-o=' + new_name])
        osmfile  = new_name

    if _args.poly:
        osmfile_list = list()
        for polyfile in _args.poly:
            if not os.path.isfile(polyfile):
                logging.warn("%s is not a file", polyfile)
                continue
            polygon_name, ext = os.path.splitext(os.path.basename(polyfile))
            osmfile_name, ext = os.path.splitext(osmfile)
            osmfile_for_area = '{0}-{1}.o5m'.format(osmfile_name, polygon_name)
            logging.info("Extracting area %s from %s to make %s", polygon_name, osmfile, osmfile_for_area)
            subprocess.check_call([OSMCONVERT, osmfile, '--complete-ways', '-B='+polyfile, '-o='+osmfile_for_area])
            osmfile_list.append(osmfile_for_area)
    else:
        setup_database(osmfile)
