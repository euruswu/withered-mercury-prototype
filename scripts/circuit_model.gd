extends RefCounted
## A direct port of the approved HTML prototype's topology.
## Each endpoint is [ring, side (o/i), slot]. Crossed drawn pipes are not junctions.

const INITIAL := [2, 4, 1]
const RINGS := [
	[["o", 0, "i", 1], ["o", 4, "i", 3], ["o", 1, "o", 2], ["i", 4, "i", 5]],
	[["o", 1, "i", 0], ["o", 3, "i", 4], ["o", 4, "o", 5], ["i", 1, "i", 2]],
	[["o", 0, "i", 2], ["o", 4, "i", 5], ["o", 1, "o", 2], ["i", 0, "i", 1]],
]

static func endpoint_key(point: Array) -> String:
	return "%d:%s:%d" % [point[0], point[1], point[2]]

static func trace(turns: Array) -> Dictionary:
	assert(turns.size() == 3, "Three ring positions are required.")
	var edges: Dictionary = {}
	for ring in range(3):
		for piece in range(RINGS[ring].size()):
			var p: Array = RINGS[ring][piece]
			var a: Array = [ring, p[0], posmod(p[1] + int(turns[ring]), 6)]
			var b: Array = [ring, p[2], posmod(p[3] + int(turns[ring]), 6)]
			var id := "r%dp%d" % [ring, piece]
			edges[endpoint_key(a)] = {"next": b, "id": id, "forward": true}
			edges[endpoint_key(b)] = {"next": a, "id": id, "forward": false}
	var node: Array = [0, "o", 0]
	var visited: Dictionary = {}
	var path: Array = []
	var core := false
	while not visited.has(endpoint_key(node)):
		visited[endpoint_key(node)] = true
		if not edges.has(endpoint_key(node)):
			return result("gap", core, path, node)
		var edge: Dictionary = edges[endpoint_key(node)]
		path.append({"id": edge.id, "forward": edge.forward})
		var point: Array = edge.next
		var ring: int = point[0]
		var side: String = point[1]
		var slot: int = point[2]
		if side == "o":
			if ring == 0:
				return result("return" if slot == 4 else "outer-gap", core, path, point)
			path.append({"id": "join%d-%d" % [ring - 1, slot], "forward": false})
			node = [ring - 1, "i", slot]
		elif ring == 2:
			if slot != 2 and slot != 5:
				return result("core-gap", core, path, point)
			if core:
				return result("loop", core, path, point)
			core = true
			path.append({"id": "core", "forward": slot == 2})
			node = [2, "i", 5 if slot == 2 else 2]
		else:
			path.append({"id": "join%d-%d" % [ring, slot], "forward": true})
			node = [ring + 1, "o", slot]
	return result("loop", core, path, node)

static func result(kind: String, core: bool, path: Array, point: Array) -> Dictionary:
	return {"kind": kind, "core": core, "path": path, "point": point,
		"success": kind == "return" and core}
