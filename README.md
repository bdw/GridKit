# GridKit is a power grid extraction toolkit

GridKit uses spatial and topological analysis to transform map objects
from OpenStreetMap into a network model of the electric power
system. It has been developed in the context of the
[SciGRID](http://scigrid.de) project at the
[Next Energy](http://www.next-energy.de/) research institute, to
investigate the possibility of 'heuristic' analysis to augment the
route-based analysis used in SciGRID. This has been implemented as a
series of scripts for the PostgreSQL database using the PostGIS
spatial extensions.

The network model is intended to be used in power systems analysis
applications, for example using the
[PYPOWER](https://rwl.github.io/PYPOWER) system, or the
[PyPSA](https://github.com/FRESNA/PyPSA) toolkit. In general this will
require the following:

* Careful interpretation of results (e.g. power lines and stations may
  have multiple voltages).
* Realistic information on generation and load in the system
  (electrical supply and demand).
* Reasonable, possibly location specific assumptions on the impedance
  of lines, depending on their internal structure. Unlike SciGRID,
  *such assumptions have not yet been applied*.

Of note, PyPSA implements several methods of network simplification,
which is in many cases essential for ensuring that the power flow
computations remain managable.


## How to Use

This software has been developed and tested on linux using PostgreSQL
9.4, PostGIS 2.1 and osm2pgsql version 0.88.1. PostgreSQL should also
support the *hstore* extension to allow the manipulation of tags, and
the *plpgsql* language should not be disabled. Some familiarity with
OpenStreetMap is preferable. Source datafiles can be acquired from
[planet.openstreetmap.org](http://planet.openstreetmap.org/pbf/) or
[geofabrik](http://download.geofabrik.de/). In many cases the latter
is preferable due to a much smaller size.

Extracting the power information from this source file is not strictly
necessary, but probably very helpful in ensuring that the running time
of the procedures remains reasonable. The use of
[osm-c-tools](https://github.com/bdw/osm-c-tools/) is recommended,
although [osmosis](http://wiki.openstreetmap.org/wiki/Osmosis) also
works.

    osmconvert my_area.osm.pbf -o=my_area.o5m
    osmfilter my_area.o5m --keep='power=*' -o=my_area_power.o5m

Alternatively for extracting a specific region from the planet file
(my\_area.poly should a
[polygon filter file](http://wiki.openstreetmap.org/wiki/Osmosis/Polygon_Filter_File_Format),
which you can acquire from
[polygons.openstreetmap.fr](http://polygons.openstreetmap.fr)):

    osmconvert planet-latest.osm.pbf -B=my_area.poly -o=my_area.o5m

### PostgreSQL configuration

GridKit assumes that you have the `psql` and `osm2pgsql` binaries
available. Configuring access to the postgresql server is implemented
using standard
[environment variables](http://www.postgresql.org/docs/9.4/static/libpq-envars.html). Thus,
prior to importing the openstreetmap source data, you should use something like:

    export PGUSER=my_username PGDATABASE=my_database PGPASSWORD=my_password

Optionally also:

    export PGHOST=server_hostname PGPORT=server_port

For more information, check out the linked documentation.

### Extraction process

Data imports are facilitated using:

    ./import-data.sh /path/to/data.o5m database_name
    
The `database_name` parameter is optional if the `PGDATABASE`
environment variable has been set. Running the extraction process is just:

    ./run.sh

You should expect this, depending on your machine and the size of your
dataset, to take anywhere from 5 minutes to a few hours. Afterwards,
you can extract a copy of the network using:

    ./psql -f export-topology.sql
    
Which will copy the network to a set of CSV files in `/tmp`:

* `/tmp/heuristic_vertices.csv` and `/tmp/heuristic_links.csv` contain
  the complete network at all voltage and frequency levels.

* `/tmp/heuristic_vertices_highvoltage` and
  `/tmp/heuristic_links_highvoltage` contain the high-voltage network
  (>220kV) at any frequency which is not 16.7Hz.


### Some things to watch out for

This process requires a lot of memory and significant amounts of CPU
time. It also makes *a lot of copies* of the same data. This is very
useful for investigating issues and tracking changes by the system. It
also means that you should probably not use this on
resource-constrained systems, such as docker containers in constrained
virtual machines or raspberry pi's.

Queries have been typically optimized to make the best possible use of
indices, but whether they are actually used is sensitive to query
planner specifics. Depending on the specifics,
[PostgreSQL tuning](https://wiki.postgresql.org/wiki/Performance_Optimization)
may be necessary to run the extraction process efficiently.

The resultant network will in almost all cases be considerably more
complex than equivalent networks (e.g. from SciGRID or the
[Bialek model](http://www.powerworld.com/knowledge-base/updated-and-validated-power-flow-model-of-the-main-continental-european-transmission-network). For
practical applications, it is highly advisable to use simplification.


## Analysis Utilities

Aside from the main codebase, some utilities have been implemented to
enable analysis of the results. Notably:

* `util/network.py` allows for some simple analysis of the network,
  transformation into a **PYPOWER** powercase dictionary, and
  'patching' of the network to propagate voltage and frequency
  information from neighbors.
* `util/load_polyfile.py` transforms a set of `poly` files into import
  statements for PostgreSQL, to allow (among other things) data
  statistics per area, among other things.
  
