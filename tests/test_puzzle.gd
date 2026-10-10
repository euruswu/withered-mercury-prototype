extends SceneTree
## Exercises actual GUI-dispatched mouse input and the live scene state.
const Scene = preload("res://scenes/mercury_puzzle.tscn")
const Model = preload("res://scripts/circuit_model.gd")
var scene
var board
var failures: Array[String] = []
var solved_count := 0
var capture_path := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture="):
			capture_path = arg.trim_prefix("--capture=")
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func run() -> void:
	root.size = Vector2i(1120, 800)
	scene = Scene.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	board = scene.board
	board.set_process(false)
	scene.sound_enabled = false
	scene._refresh_text()
	scene.solved.connect(func(): solved_count += 1)
	check(board.turns == [2, 4, 1], "Initial layout differs from approved prototype.")
	await capture("01-initial")
	# One click is exactly one clockwise step.
	await pointer_at(0, 0.0, true)
	await pointer_at(0, 0.0, false)
	board._process(1.0)
	check(board.turns == [3, 4, 1], "Click did not rotate exactly one step.")
	# A 60-degree drag must not also trigger a release click.
	await pointer_at(0, 0.0, true)
	await drag_to(0, PI / 6.0)
	await drag_to(0, PI / 3.0)
	await pointer_at(0, PI / 3.0, false)
	board._process(1.0)
	check(board.turns == [4, 4, 1], "Drag release added an unwanted step.")
	# Anticlockwise snapping and tiny-drag click discrimination.
	await pointer_at(1, 0.0, true)
	await drag_to(1, -PI / 3.0)
	await pointer_at(1, -PI / 3.0, false)
	board._process(1.0)
	check(board.turns == [4, 3, 1], "Anticlockwise drag did not snap correctly.")
	# Losing application focus rolls an unfinished gesture back to its initial detent.
	await pointer_at(2, 0.0, true)
	await drag_to(2, PI * 0.4)
	board._notification(MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	board._process(1.0)
	await pointer_at(2, PI * 0.4, false)
	check(board.turns == [4, 3, 1] and board.drag_ring == -1,
		"Focus loss retained an unfinished drag.")
	# Keyboard controls must route through the real input pipeline too.
	scene.reset_puzzle()
	await key_press(KEY_2)
	await key_press(KEY_RIGHT)
	board._process(1.0)
	check(board.turns == [2, 5, 1], "Keyboard selection/rotation failed.")
	# Test failure follows the graph and never emits solved.
	scene.reset_puzzle()
	scene.start_test()
	check(scene.test_button.disabled, "Test button remained active during flow.")
	var unchanged: Array = board.turns.duplicate()
	board.rotate_ring(0)
	check(board.turns == unchanged, "Rings moved during a flow test.")
	board._process(99.0)
	check(not board.circuit_ready and solved_count == 0, "An unsolved layout reported success.")
	await capture("02-stopped-flow")
	# Reset while animating leaves no stale completion callback or silver trail.
	scene.start_test()
	board._process(0.1)
	scene.reset_puzzle()
	board._process(99.0)
	check(not board.testing and board.completed.is_empty() and not board.circuit_ready,
		"Reset during flow left stale state.")
	# All traced segments must meet their neighbours visually in every state.
	for a in range(6):
		for b in range(6):
			for c in range(6):
				set_layout([a, b, c])
				var result := Model.trace([a, b, c])
				var route: Array = [{"id": "source", "forward": true}]
				route.append_array(result.path)
				if result.success:
					route.append({"id": "return", "forward": true})
				for i in range(1, route.size()):
					var previous: PackedVector2Array = board.paths[route[i - 1].id]
					var current: PackedVector2Array = board.paths[route[i].id]
					var end: Vector2 = previous[-1] if route[i - 1].forward else previous[0]
					var start: Vector2 = current[0] if route[i].forward else current[-1]
					check(end.distance_to(start) < 0.05, "A drawn pipe does not meet the next segment.")
	set_layout([2, 2, 0])
	scene.start_test()
	board._process(99.0)
	check(board.passed_core and not board.circuit_ready, "Core-only flow incorrectly wins.")
	await capture("03-core-return-gap")
	# Solve using the actual rotation API, starting from the approved layout.
	scene.reset_puzzle()
	for ring in range(3):
		for i in range([4, 2, 5][ring]):
			board.rotate_ring(ring)
			board._process(1.0)
	scene.start_test()
	board._process(99.0)
	check(board.circuit_ready and solved_count == 1, "A complete return failed to emit solved.")
	check(board.completed.has("return"), "Return-to-reservoir animation is missing.")
	await capture("04-solved")
	scene._toggle_language()
	await capture("05-english")
	# Rotating again invalidates readiness, and reset restores the original puzzle.
	board.rotate_ring(2)
	board._process(1.0)
	check(not board.circuit_ready and board.completed.is_empty(), "Rotation retained stale success state.")
	scene.reset_puzzle()
	check(board.turns == [2, 4, 1], "Reset did not restore the initial layout.")
	# Narrower viewport remains usable (a landscape desktop toy).
	root.size = Vector2i(900, 680)
	await process_frame
	await process_frame
	await capture("06-small-window")
	if failures.is_empty():
		print("PASS: GUI click, bidirectional drag, snap, flow locking, reset, signals, and replay.")
		print("PASS: rendered path continuity for all 216 configurations.")
		quit(0)
	else:
		print("FAILED: ", failures)
		quit(1)

func set_layout(turns: Array) -> void:
	board.reset_puzzle()
	board.turns = turns.duplicate()
	for ring in range(3):
		board.visual_angles[ring] = float(turns[ring]) * board.STEP
		board.target_angles[ring] = board.visual_angles[ring]
	board._build_paths()
	board.queue_redraw()

func pointer_position(ring: int, angle: float) -> Vector2:
	var radius: float = (board.METRICS[ring][0] + board.METRICS[ring][1]) * 0.5
	var local: Vector2 = board.CENTER + Vector2.from_angle(angle) * radius
	return board.global_position + board.board_to_control(local)

func pointer_at(ring: int, angle: float, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = pointer_position(ring, angle)
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame

func drag_to(ring: int, angle: float) -> void:
	var event := InputEventMouseMotion.new()
	event.position = pointer_position(ring, angle)
	event.global_position = event.position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(event)
	await process_frame

func key_press(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame

func capture(name: String) -> void:
	if capture_path.is_empty() or DisplayServer.get_name() == "headless":
		return
	board.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(capture_path)
	var image := root.get_texture().get_image()
	image.save_png(capture_path.path_join(name + ".png"))
