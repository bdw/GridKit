from __future__ import unicode_literals, division, print_function
import io
import csv
import random
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

        # if no loads map is passed,
        # generate an 'electrified pair' of two random
        # nodes, one of which delivers power, the other consumes it
        if loads is None:
            loads = self._electrified_pair()
        ppc = {
            "version": 2,
            "baseMVA": 100.0
        }
        nodes        = list()
        transformers = list()
        generators   = list()
        edges        = list()

        station_to_bus = dict()
        next_bus_id    = 1
        for station in self.station.itervalues():
            # because we do a DC PF, we ignore frequencies completely
            pass

    def _electrified_pair(self):
        src, dst = random.sample(self.stations, 2)
        return {
            src: 100, # MW
            dst: 50,  # MW
        }

    def _make_bus(self, station, voltage, load, bus_id):
        # see pypower.caseformat for documentation on how this works
        area_nr = self._area_number(station.operator)
        base_kv  = station.voltage // 1000
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

    def _make_transformer(self, from_bus, to_bus, from_voltage, to_voltage):
        return [
            from_bus,
            to_bus,
        ]

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

