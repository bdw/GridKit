from __future__ import unicode_literals, division, print_function
import io
import csv
import random
import itertools
from recordclass import recordclass
from numpy import array

class Station(recordclass('Station', b'station_id name operator voltages frequencies lines')):
    def __hash__(self):
        return hash(self.station_id)

class Line(recordclass('Line', b'line_id operator left right frequency voltage resistance reactance capacitance')):
    def __hash__(self):
        return hash(self.line_id)

    def __repr__(self):
        return "{0}: {1} -> {2}".format(self.line_id, self.left.name, self.right.name).encode('utf-8')

    @property
    def susceptance(self):
        if self.capacitance is None or self.frequency is None:
            return None
        return self.capacitance * self.frequency

class Network(object):
    def __init__(self):
        self.stations = dict()
        self.lines    = dict()
        self._areas   = dict()

    def connected_sets(self):
        # bfs algorithm to find connected sets in the network
        unseen = set(self.stations.values())
        connected = []
        while unseen:
            current = []
            root  = unseen.pop()
            queue = [root]
            while queue:
                node = queue.pop()
                if node in unseen:
                    unseen.remove(node)
                    current.append(node)
                for line in node.lines:
                    if line.left in unseen:
                        queue.append(line.left)
                    if line.right in unseen:
                        queue.append(line.right)
            connected.append(current)
        return connected

    def patch(self):
        # flood algorithm to patch all lines and stations with values from neighbours
        totals = list()
        while True:
            changes = 0
            for station in self.stations.itervalues():
                line_voltages    = [line.voltage for line in station.lines if line.voltage is not None]
                line_frequencies = [line.frequency for line in station.lines if line.frequency is not None]
                if station.voltages is None:
                    if line_voltages:
                        station.voltages = list(set(line_voltages))
                        changes         += 1
                # what about conflicting voltages?
                elif any(lv not in station.voltages for lv in line_voltages):
                    station.voltages = list(set(station.voltages + line_voltages))
                    changes += 1

                if station.frequencies is None:
                    if line_frequencies:
                        station.frequencies = list(set(line_frequencies))
                        changes += 1
                elif any(lf not in station.frequencies for lf in line_frequencies):
                    station.frequencies = list(set(station.frequencies + line_frequencies))
                    changes += 1

            for line in self.lines.itervalues():
                if line.frequency is None:
                    if line.left.frequencies is not None:
                        if line.right.frequencies is not None:
                            shared_frequency = set(line.left.frequencies) & set(line.right.frequencies)
                            if shared_frequency:
                                line.frequency = max(shared_frequency)
                                changes += 1
                        elif len(line.left.frequencies) == 1:
                            line.frequency = line.left.frequencies[0]
                            changes += 1
                    elif line.right.frequencies is not None and len(line.right.frequencies) == 1:
                        line.frequency = line.right.frequencies[0]
                        changes += 1

                if line.voltage is None:
                    # this never seems to happen though!
                    if line.left.voltages is not None:
                        if line.right.voltages is not None:
                            shared_voltage = set(line.left.voltages) & set(line.right.voltages)
                            if shared_voltage:
                                line.voltage = max(shared_voltage)
                                changes += 1
                        elif len(line.left.voltages) == 1:
                            line.voltage = line.left.voltages[0]
                            changes += 1
                    elif line.right.frequencies is not None and len(line.right.frequencies == 1):
                        line.frequency = line.right.frequencies[0]

            if changes == 0:
                break
            totals.append(changes)

        return totals

    def report(self):
        # calculate missing values statically
        broken_stations = 0
        broken_lines    = 0
        mismatches      = 0
        for station in self.stations.itervalues():
            if station.voltages is None or station.frequencies is None:
                broken_stations += 1
            for line in station.lines:
                if station.frequencies is not None:
                    if line.frequency not in station.frequencies:
                        mismatches += 1
                        continue
                elif line.frequency is not None:
                    mismatches += 1
                    continue
                if station.voltages is not None:
                    if line.voltage not in station.voltages:
                        mismatches += 1
                        continue
                elif line.voltage is not None:
                    mismatches += 1
                    continue

        for line in self.lines.itervalues():
            if line.voltage is None or line.frequency is None:
                broken_lines += 1
        return broken_stations, broken_lines, mismatches

    def _area_number(self, area_name):
        if area_name not in self._areas:
            # assign next area number
            self._areas[area_name] = len(self._areas) + 1
        return self._areas[area_name]

    def powercase(self, loads=None):
        # loads is a map of station id -> load, either positive or
        # negative; a negative load is represented by a generator.

        # if no loads map is passed, generate an 'electrified pair' of
        # two random nodes, one of which delivers power, the other
        # consumes it
        if loads is None:
            loads = self._electrified_pair()
        ppc = {
            "version": 2,
            "baseMVA": 100.0
        }
        nodes        = list()
        edges        = list()
        generators   = list()

        station_to_bus = dict()
        bus_id_gen     = itertools.count()

        for station in self.stations.itervalues():
            # because we do a DC PF, we ignore frequencies completely
            minv, maxv = min(station.voltages), max(station.voltages)
            for voltage in station.voltages:
                if station.station_id in loads and voltage == minv:
                    bus_load = loads[station.station_id]
                else:
                    bus_load = 0
                bus_id = next(bus_id_gen)
                station_to_bus[station.station_id, voltage] = bus_id
                if bus_load < 0:
                    # it is a generator instead of a load, insert it
                    generators.append(self._make_generator(bus_id, -bus_load))
                    bus_load = 0
                nodes.append(self._make_bus(station, voltage, bus_load, bus_id))

            for voltage in station.voltages:
                if voltage != maxv:
                    # create a transformer branch from max voltage to this voltage
                    from_bus = station_to_bus[station.station_id, maxv]
                    to_bus   = station_to_bus[station.station_id, voltage]
                    edges.append(self._make_transformer(from_bus, to_bus))

        for line in self.lines.itervalues():
            # create branches between stations
            from_bus = station_to_bus[line.left.station_id, line.voltage]
            to_bus   = station_to_bus[line.right.station_id, line.voltage]
            edges.append(self._make_line(line, from_bus, to_bus))

        ppc['bus']    = array(nodes)
        ppc['gen']    = array(generators)
        ppc['branch'] = array(edges)
        return ppc

    def _electrified_pair(self):
        src, dst = random.sample(self.stations, 2)
        return {
            src: -100, # MW
            dst: 50,  # MW
        }

    def _make_bus(self, station, voltage, load, bus_id):
        # see pypower.caseformat for documentation on how this works
        area_nr  = self._area_number(station.operator)
        base_kv  = voltage // 1000
        return [
            bus_id,
            3,       # slack bus
            load,    # real load in MW
            0,       # reactive load MVAr, zero because DC
            0,       # shunt conductance
            0,       # shunt susceptance
            area_nr, # area number
            1.0,     # voltage magnitude per unit
            0,       # voltage angle
            base_kv, # base voltage (per unit base)
            area_nr, # loss zone nr
            1.1,     # max voltage per unit
            0.9,     # min voltage per unit
        ]

    def _make_transformer(self, from_bus, to_bus):
        return [
            from_bus,
            to_bus,
            0.01,      # resistance
            0.01,      # reactance
            0.01,      # line charging susceptance
            200,       # long term rating (MW)
            200,       # short term rating (MW)
            200,       # emergency rating (MW)
            1,         # off-nominal (correction) taps ratio, 1 for no correction
            0,         # transformer phase shift angle,
            1,         # status (1 = on)
            -360,      # minimum angle
            360,       # maximum angle
        ]

    def _make_line(self, line, from_bus, to_bus):
        return [
            from_bus,
            to_bus,
            line.resistance or 0.01,   # default value if None
            line.reactance or 0.01,
            line.susceptance or 0.01,
            200,
            200,
            200,
            0,                          # not a transformer
            0,                          # not a transformer
            1,                          # status
            -360,
            360
        ]

    def _make_generator(self, bus_id, power_output):
        return [
            bus_id,
            power_output,
            0,             # reactive power output
            0,             # maximum reactive power output
            0,             # minimum reactive power output
            1.0,           # per-unit voltage magnitude setpoint
            100,           # base MVA
            1,             # status (on)
            power_output,  # maximum real power output
            0,             # minimum real power output
            0,             # Pc1, irrelevant
            0,             # Pc2
            0,             # Qc1min
            0,             # Qc1max
            0,             # Qc2min
            0,             # Qc2max
            5,             # ramp rate load-following (MW/min)
            5,             # ramp rate 10-min reserve (MW/min)
            5,             # ramp rate 30-min reserve (MW/min)
            0,             # ramp rate reactive power
            0,             # area participation factor
        ]
        pass


    def dot(self):
        buf = io.StringIO()
        buf.write("graph {\n")
        buf.write("rankdir LR\n")
        for station in self.stations.itervalues():
            buf.write('s_{0} [label="{1}"]\n'.format(station.station_id, station.name.replace('"', "'")))
        for line in self.lines.itervalues():
            buf.write('s_{0} -- s_{1}\n'.format(line.left.station_id, line.right.station_id))
        buf.write("}\n")
        return buf.getvalue()

    def __repr__(self):
        return "Network of {0} stations, {1} lines".format(len(self.stations), len(self.lines)).encode('utf-8')


class ScigridNetwork(Network):
    class _csv_dialect(csv.excel):
        quotechar = b"'"

    def read(self, vertices_csv, links_csv):
        with io.open(vertices_csv, 'rb') as handle:
            for row in csv.DictReader(handle, dialect=self._csv_dialect):
                station_id  = row['v_id']
                name        = row['name'].decode('utf-8')
                operator    = row['operator'].decode('utf-8')
                voltages    = map(int, row['voltage'].decode('utf-8').split(';')) if row['voltage'] else None
                frequencies = map(float, row['frequency'].decode('utf-8').split(';')) if row['frequency'] else None
                self.stations[row['v_id']] = Station(station_id=station_id, name=name, operator=operator,
                                                     voltages=voltages, frequencies=frequencies, lines=list())

        with io.open(links_csv, 'rb') as handle:
            for i, row in enumerate(csv.DictReader(handle, dialect=self._csv_dialect)):
                line_id     = row['l_id']
                operator    = row['operator'].decode('utf-8')
                left        = self.stations[row['v_id_1']]
                right       = self.stations[row['v_id_2']]

                resistance  = float(row['r_ohmkm']) * int(row['length_m']) / 1000 if row['r_ohmkm'] else None
                reactance   = float(row['x_ohmkm']) * int(row['length_m']) / 1000 if row['x_ohmkm'] else None
                capacitance = float(row['c_nfkm']) * int(row['length_m']) / 1000  if row['c_nfkm'] else  None
                frequency   = float(row['frequency']) if row['frequency'] else None
                voltage     = int(row['voltage']) if row['voltage'] else None

                line  = Line(line_id=line_id, operator=operator, left=left, right=right,
                             voltage=voltage, frequency=frequency,
                             resistance=resistance, reactance=reactance, capacitance=capacitance)
                self.lines[row['l_id']] = line
                left.lines.append(line)
                right.lines.append(line)

