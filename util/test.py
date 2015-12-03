import io
import geometry
import polyfile

parser = polyfile.PolyfileParser()
with io.open('germany.poly', 'r', encoding='utf-8') as handle:
    germany_parsed = parser.parse(handle.read())
    germany_polygon = geometry.Polygon(germany_parsed[1]['1'])
    print((7, 52) in germany_polygon)
    print((5, 52) in germany_polygon)
    print((7, 54) in germany_polygon)
    print((7, 41) in germany_polygon)
