extends SceneTree
const Model = preload("res://scripts/circuit_model.gd")
# Captured from the original approved HTML's trace(), before the Godot port.
# Includes every traversed pipe, traversal direction, stop point and outcome.
const REFERENCE_SHA256 := "d53b29ba594ef8e4fb243cc053710112d87d7c1ad279c802f3d4ea9a9e3516b2"

func _initialize() -> void:
	var signature := ""
	var wins: Array = []
	var counts: Dictionary = {}
	for a in range(6):
		for b in range(6):
			for c in range(6):
				var trace := Model.trace([a, b, c])
				var pipes := PackedStringArray()
				for segment in trace.path:
					pipes.append(segment.id + (">" if segment.forward else "<"))
				var point: Array = trace.point
				signature += "%d%d%d|%s|%d|%d:%s:%d|%s\n" % [
					a, b, c, trace.kind, int(trace.core), point[0], point[1], point[2], ",".join(pipes)]
				counts[trace.kind] = counts.get(trace.kind, 0) + 1
				if trace.success:
					wins.append([a, b, c])
				if Model.trace([a + 6, b - 6, c + 12]) != trace:
					fail("Full revolutions changed the result.")
					return
	if signature.sha256_text() != REFERENCE_SHA256:
		fail("Godot trace differs from the original HTML: " + signature.sha256_text())
		return
	if wins != [[0, 0, 0]]:
		fail("Expected exactly one solution; found " + str(wins))
		return
	for turns in [[2, 2, 0], [2, 4, 0]]:
		var result := Model.trace(turns)
		if not result.core or result.success:
			fail("Reaching the core alone must not win.")
			return
	print("PASS: all 216 traces match the original HTML, including pipe directions.")
	print("PASS: unique solution; incomplete return rejected; full revolutions invariant.")
	print("Outcomes: ", counts)
	quit(0)

func fail(message: String) -> void:
	push_error(message)
	quit(1)
