from __future__ import division, print_function
import io
import operator
import collections
import polyfile
from geometry import edges

parser = polyfile.PolyfileParser()

with io.open('germany.poly', 'r', encoding='utf-8') as handle:
    germany = parser.parse(handle.read())


germany_points = germany[1]['1']
extents = ((y1, y2) for ((x1, y1), (x2, y2)) in edges(germany_points))
prepared_extents = sorted((min(x1,x2),max(x1,x2), i) for (i, (x1, x2)) in enumerate(extents))

# we need a binary tree, because...
Node = collections.namedtuple('Node', ['left','right','interval', 'value'])
def build_tree(extents, left=0, right=-1):
    if right < 0:
        right = len(extents)
    if right == left or left + 1 == right:
        # leaf node
        return Node(None, None, extents[left][0:2], extents[left][2])
    else:
        # I have children!
        mid = (right - left) // 2 + left
        left_node = build_tree(extents, left, mid)
        right_node = build_tree(extents, mid, right)
        # want to know the union of the interval of the children
        # by construction, the minimum is the minimum of the left-interval
        # the maximum might be the maximum or the left or right interval
        interval = left_node.interval[0], max(left_node.interval[1], right_node.interval[1])
        return Node(left_node, right_node, interval, None)

print(build_tree([(0,1,0)], 0, 0))
print(build_tree([(0,1,0),(0.5,0.7,2)]))
print(build_tree([(0,1,0),(0.5,0.7,1),(0.7,1.1,2)]))

tree = build_tree(prepared_extents)
def query_tree(tree, x):
    min_x, max_x = tree.interval
    results = []
    if min_x > x or max_x < x:
        return results
    if tree.left is not None:
        results.extend(query_tree(tree.left, x))
    if tree.right is not None:
        results.extend(query_tree(tree.right, x))
    if tree.value is not None:
        results.append(tree.value)
    return results
        
edge_idxs = query_tree(tree, 52.0)
edge_list = list(edges(germany_points))
print(list(edge_list[i] for i in edge_idxs))
try:
    import matplotlib.pyplot as plt
    border_x, border_y = zip(*germany_points)
    plt.plot(border_x, border_y, 'black')
    edge_list = list(edges(germany_points))
    for i in edge_idxs:
        edge = edge_list[i]
        print(edge)
        lon, lat = zip(*edge)
        plt.plot(lon, lat, 'blue')
    plt.show()
except ImportError:
    print("could not import matplotlib")

