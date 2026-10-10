extends Control
## Native vector board: rendering, detent input and animated flow.
## Puzzle state always uses integral slots; only the visual angles are continuous.

signal configuration_changed
signal busy_changed
signal flow_finished(success: bool, kind: String)
signal ring_selected(index: int)

const Model = preload("res://scripts/circuit_model.gd")
const BASE_SIZE := Vector2(720, 660)
const CENTER := Vector2(360, 350)
const RADIUS := 238.0
const STEP := TAU / 6.0
const METRICS := [[238.0, 177.31], [171.60, 109.48], [103.77, 44.03]]
const SILVER := Color("e4f0e9")
const RIM := Color("929279")
const RED := Color("db886d")
const BLUE := Color("8bd1de")
const GOLD := Color("c5b386")

var turns: Array = Model.INITIAL.duplicate()
var visual_angles: Array[float] = [2.0 * STEP, 4.0 * STEP, STEP]
var target_angles: Array[float] = visual_angles.duplicate()
var selected_ring := 0
var hovered_ring := -1
var drag_ring := -1
var press_point := Vector2.ZERO
var last_pointer_angle := 0.0
var drag_origin_angle := 0.0
var moved := false
var snapping := false
var testing := false
var circuit_ready := false
var last_result: Dictionary = {}
var paths: Dictionary = {}
var sequence: Array = []
var completed: Dictionary = {}
var segment_index := 0
var distance_in_segment := 0.0
var passed_core := false
var animation_speed := 220.0
var font: Font
var language := "zh"

func _ready() -> void:
	custom_minimum_size = Vector2(500, 480)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	mouse_exited.connect(func(): hovered_ring = -1; queue_redraw())
	_build_paths()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and drag_ring >= 0:
		_cancel_drag()

func _scale_factor() -> float:
	return minf(size.x / BASE_SIZE.x, size.y / BASE_SIZE.y)

func _origin() -> Vector2:
	return (size - BASE_SIZE * _scale_factor()) * 0.5

func _local_point(point: Vector2) -> Vector2:
	return (point - _origin()) / maxf(_scale_factor(), 0.01)

func board_to_control(point: Vector2) -> Vector2:
	return _origin() + point * _scale_factor()

func hit_ring(point: Vector2) -> int:
	var radius := point.distance_to(CENTER)
	for ring in range(3):
		if radius <= METRICS[ring][0] + 2.0 and radius >= METRICS[ring][1] - 2.0:
			return ring
	return -1

func is_busy() -> bool:
	return testing or snapping or drag_ring >= 0

func select_ring(index: int) -> void:
	selected_ring = clampi(index, 0, 2)
	ring_selected.emit(selected_ring)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var point := _local_point(event.position)
		hovered_ring = hit_ring(point)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if hovered_ring >= 0 else Control.CURSOR_ARROW
		if drag_ring >= 0:
			_update_drag(point)
		queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var point := _local_point(event.position)
		if event.pressed and not is_busy():
			var ring := hit_ring(point)
			if ring < 0:
				return
			grab_focus()
			select_ring(ring)
			_clear_flow()
			drag_ring = ring
			press_point = point
			last_pointer_angle = (point - CENTER).angle()
			drag_origin_angle = visual_angles[ring]
			moved = false
			busy_changed.emit()
			accept_event()
		elif not event.pressed and drag_ring >= 0:
			_update_drag(point)
			var ring := drag_ring
			drag_ring = -1
			if not moved:
				_set_target(ring, drag_origin_angle + STEP)
			else:
				_set_target(ring, roundf(visual_angles[ring] / STEP) * STEP)
			accept_event()

func _update_drag(point: Vector2) -> void:
	if point.distance_to(press_point) > 7.0:
		moved = true
	# Avoid undefined angular movement when the pointer crosses the center.
	if point.distance_to(CENTER) < 20.0:
		return
	var angle := (point - CENTER).angle()
	var delta := wrapf(angle - last_pointer_angle, -PI, PI)
	if moved:
		visual_angles[drag_ring] += delta
	last_pointer_angle = angle
	_build_paths()

func _cancel_drag() -> void:
	var ring := drag_ring
	drag_ring = -1
	_set_target(ring, drag_origin_angle)

func rotate_ring(ring: int, direction: int = 1) -> void:
	if is_busy():
		return
	select_ring(ring)
	_clear_flow()
	_set_target(ring, visual_angles[ring] + STEP * direction)

func _set_target(ring: int, angle: float) -> void:
	target_angles[ring] = angle
	turns[ring] = posmod(roundi(angle / STEP), 6)
	snapping = true
	configuration_changed.emit()
	busy_changed.emit()
	queue_redraw()

func _clear_flow() -> void:
	circuit_ready = false
	last_result.clear()
	completed.clear()
	sequence.clear()
	passed_core = false
	distance_in_segment = 0.0
	segment_index = 0

func reset_puzzle() -> void:
	testing = false
	snapping = false
	drag_ring = -1
	turns = Model.INITIAL.duplicate()
	for ring in range(3):
		visual_angles[ring] = float(turns[ring]) * STEP
		target_angles[ring] = visual_angles[ring]
	_clear_flow()
	_build_paths()
	configuration_changed.emit()
	busy_changed.emit()
	queue_redraw()

func start_test() -> void:
	if is_busy():
		return
	_clear_flow()
	_build_paths()
	last_result = Model.trace(turns)
	sequence = [{"id": "source", "forward": true}]
	sequence.append_array(last_result.path)
	if last_result.success:
		sequence.append({"id": "return", "forward": true})
	testing = true
	busy_changed.emit()
	queue_redraw()

func _process(delta: float) -> void:
	if snapping:
		var done := true
		for ring in range(3):
			visual_angles[ring] = move_toward(visual_angles[ring], target_angles[ring], delta * 7.0)
			if not is_equal_approx(visual_angles[ring], target_angles[ring]):
				done = false
		_build_paths()
		if done:
			snapping = false
			for ring in range(3):
				visual_angles[ring] = float(turns[ring]) * STEP
				target_angles[ring] = visual_angles[ring]
			_build_paths()
			busy_changed.emit()
		queue_redraw()
	if testing:
		distance_in_segment += delta * animation_speed
		while segment_index < sequence.size():
			var id: String = sequence[segment_index].id
			var length := _path_length(paths[id])
			if distance_in_segment < length:
				break
			distance_in_segment -= length
			completed[id] = sequence[segment_index].forward
			if id == "core":
				passed_core = true
			segment_index += 1
		if segment_index == sequence.size():
			testing = false
			circuit_ready = last_result.success
			busy_changed.emit()
			flow_finished.emit(circuit_ready, last_result.kind)
		queue_redraw()

func _point(radius: float, slot: float) -> Vector2:
	return CENTER + Vector2.from_angle(-PI * 0.5 + slot * STEP) * radius

func _arc_points(radius: float, from_slot: float, delta_slots: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var steps := maxi(8, ceili(absf(delta_slots) * 22.0))
	for n in range(steps + 1):
		points.append(_point(radius, from_slot + delta_slots * float(n) / steps))
	return points

func _piece_path(ring: int, piece: Array) -> PackedVector2Array:
	var outer: float = METRICS[ring][0]
	var inner: float = METRICS[ring][1]
	var first_r := outer if piece[0] == "o" else inner
	var last_r := outer if piece[2] == "o" else inner
	var a: float = float(piece[1]) + visual_angles[ring] / STEP
	var b: float = float(piece[3]) + visual_angles[ring] / STEP
	var middle := (outer + inner) * 0.5
	if piece[0] == piece[2]:
		middle = outer - (outer - inner) * 0.2 if piece[0] == "o" else inner + (outer - inner) * 0.2
	var diff: int = posmod(int(piece[3]) - int(piece[1]), 6)
	if diff > 3:
		diff -= 6
	var points := PackedVector2Array([_point(first_r, a)])
	points.append_array(_arc_points(middle, a, float(diff)))
	points.append(_point(last_r, b))
	return points

func _build_paths() -> void:
	paths.clear()
	for ring in range(3):
		for piece in range(Model.RINGS[ring].size()):
			paths["r%dp%d" % [ring, piece]] = _piece_path(ring, Model.RINGS[ring][piece])
	for ring in range(2):
		for slot in range(6):
			paths["join%d-%d" % [ring, slot]] = PackedVector2Array([
				_point(METRICS[ring][1], slot), _point(METRICS[ring + 1][0], slot)])
	var core := PackedVector2Array()
	var a := _point(METRICS[2][1], 2)
	var b := CENTER + Vector2(23, -8)
	var c := CENTER + Vector2(-23, 8)
	var d := _point(METRICS[2][1], 5)
	for i in range(33):
		var t := float(i) / 32.0
		core.append(a.bezier_interpolate(b, c, d, t))
	paths["core"] = core
	paths["source"] = PackedVector2Array([Vector2(367, 70), Vector2(367, 99), _point(RADIUS, 0)])
	var returning := PackedVector2Array([_point(RADIUS, 4)])
	returning.append_array(_arc_points(RADIUS * 1.125, 4, 2))
	returning.append(Vector2(353, CENTER.y - RADIUS * 1.125))
	returning.append(Vector2(353, 70))
	paths["return"] = returning

func _path_length(points: PackedVector2Array) -> float:
	var length := 0.0
	for i in range(1, points.size()):
		length += points[i - 1].distance_to(points[i])
	return length

func _partial_path(points: PackedVector2Array, distance: float, forward: bool) -> PackedVector2Array:
	var ordered := points.duplicate()
	if not forward:
		ordered.reverse()
	var out := PackedVector2Array([ordered[0]])
	for i in range(1, ordered.size()):
		var length := ordered[i - 1].distance_to(ordered[i])
		if distance < length:
			out.append(ordered[i - 1].lerp(ordered[i], distance / maxf(length, 0.001)))
			break
		out.append(ordered[i])
		distance -= length
	return out

func _pipe(points: PackedVector2Array) -> void:
	draw_polyline(points, Color("0c1715"), 12.0, true)
	draw_polyline(points, Color("82918a"), 7.0, true)
	draw_polyline(points, Color("b7c2b5"), 1.2, true)

func _silver_path(points: PackedVector2Array) -> void:
	if points.size() < 2:
		return
	draw_polyline(points, Color(0.67, 0.9, 0.87, 0.13), 11.0, true)
	draw_polyline(points, SILVER, 4.5, true)

func _label(text: String, point: Vector2, color: Color = RIM, font_size: int = 14, centered: bool = true) -> void:
	if font == null:
		return
	var pos := point
	if centered:
		pos.x -= font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * 0.5
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw() -> void:
	if paths.is_empty():
		return
	draw_set_transform(_origin(), 0, Vector2.ONE * _scale_factor())
	# Worn instrument case, exposed fixings and concentric guide marks.
	draw_circle(CENTER + Vector2(0, 5), RADIUS + 21, Color(0, 0, 0, 0.22))
	draw_circle(CENTER, RADIUS + 17, Color("41493b"))
	draw_arc(CENTER, RADIUS + 17, 0, TAU, 160, RIM, 1.5, true)
	draw_circle(CENTER, RADIUS + 8, Color("1b2922"))
	for i in range(24):
		var p := _point(RADIUS + 12, float(i) / 4.0)
		if i % 2 == 0:
			draw_circle(p, 3.1, Color("adb096"))
			draw_line(p - Vector2(1.6, 0.8), p + Vector2(1.6, 0.8), Color("374339"), 1.2, true)
	for ring in range(3):
		var outer: float = METRICS[ring][0]
		var inner: float = METRICS[ring][1]
		var col := Color("35473a")
		if ring == hovered_ring or ring == drag_ring:
			col = Color("465642")
		draw_arc(CENTER, (outer + inner) / 2, 0, TAU, 160, col, outer - inner - 2.0, true)
		draw_arc(CENTER, outer, 0, TAU, 160, Color("697960"), 1.1, true)
		draw_arc(CENTER, inner, 0, TAU, 120, Color("697960"), 1.1, true)
		if ring == selected_ring:
			draw_arc(CENTER, outer - 2, -0.23, 0.23, 18, GOLD, 2.5, true)
		for slot in range(6):
			for radius in [outer, inner]:
				draw_circle(_point(radius, slot), 2.5, Color("111e18"))
		for piece in range(Model.RINGS[ring].size()):
			var points: PackedVector2Array = paths["r%dp%d" % [ring, piece]]
			_pipe(points)
			for p in [points[0], points[points.size() - 1]]:
				draw_circle(p, 5.2, RIM)
				draw_circle(p, 2.8, Color("17251c"))
	for ring in range(2):
		for slot in range(6):
			_pipe(paths["join%d-%d" % [ring, slot]])
	draw_circle(CENTER, 37, Color("203b33"))
	draw_arc(CENTER, 37, 0, TAU, 64, RIM, 1.5, true)
	_pipe(paths["core"])
	_pipe(paths["source"])
	_pipe(paths["return"])
	for id in completed:
		_silver_path(paths[id])
	if testing and segment_index < sequence.size():
		var part: Dictionary = sequence[segment_index]
		var points := _partial_path(paths[part.id], distance_in_segment, part.forward)
		_silver_path(points)
		draw_circle(points[points.size() - 1], 3.3, SILVER)
	var lamp := BLUE if circuit_ready else (SILVER if passed_core else RED)
	draw_arc(CENTER, 24, 0, TAU, 64, Color(lamp, 0.12), 10, true)
	draw_arc(CENTER, 24, 0, TAU, 64, lamp, 2.4, true)
	# Reservoir is drawn over its two connected pipes.
	draw_style_box(_tank_style(), Rect2(342, 24, 36, 46))
	draw_rect(Rect2(347, 46, 26, 18), SILVER)
	draw_line(Vector2(348, 47), Vector2(372, 47), Color.WHITE, 1, true)
	_label("储液罐" if language == "zh" else "RESERVOIR", Vector2(360, 15), RIM, 13)
	_label("出" if language == "zh" else "OUT", Vector2(397, 110), RIM, 12)
	_label("回" if language == "zh" else "RETURN", _point(RADIUS, 4) + Vector2(-28, 18), RIM, 12)
	_label("核心" if language == "zh" else "CORE", CENTER + Vector2(0, 63), Color("c1c8ac"), 13)
	if not testing and not last_result.is_empty() and not circuit_ready:
		var point: Array = last_result.point
		var radius: float = METRICS[point[0]][0 if point[1] == "o" else 1]
		var p := _point(radius, point[2])
		draw_circle(p, 11, Color(RED, 0.13))
		draw_circle(p, 5, RED)
		draw_arc(p, 8, 0, TAU, 32, RED, 1, true)
	_label("拖动管环 · 松手吸附 · 单击转一格" if language == "zh" else "DRAG · RELEASE TO SNAP · CLICK TO STEP", Vector2(360, 644), Color("aeb79c"), 14)
	draw_set_transform(Vector2.ZERO)

func _tank_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("647f72")
	style.border_color = RIM
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	return style
