extends Control
## Standalone puzzle scene. Embed it in a room and connect solved to machine readiness.
signal solved
signal readiness_changed(is_ready: bool)

const Board = preload("res://scripts/circuit_board.gd")
const FACE = preload("res://assets/fonts/MercurySans.ttf")
const INK := Color("e4e7d8")
const MUTED := Color("a2b097")
const LINE := Color("4a5c4c")
const GOLD := Color("c8b68d")
const BLUE := Color("8bd1de")
const RED := Color("db886d")

var board: Control
var language := "zh"
var status_kind := "initial"
var title_label: Label
var subtitle_label: Label
var goal_label: Label
var note_label: Label
var note_heading: Label
var status_label: Label
var status_heading: Label
var footer_label: Label
var ring_labels: Array[Button] = []
var turn_buttons: Array[Button] = []
var test_button: Button
var reset_button: Button
var language_button: Button
var sound_button: Button
var sound_enabled := true
var tick_player: AudioStreamPlayer
var finish_player: AudioStreamPlayer

func _ready() -> void:
	var app_theme := Theme.new()
	app_theme.default_font = FACE
	app_theme.default_font_size = 16
	theme = app_theme
	_build_ui()
	_build_audio()
	_refresh_text()
	board.grab_focus()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("111d19"))
	# Sparse drafting lines are part of the instrument's backing plate.
	for x in range(24, int(size.x), 28):
		draw_line(Vector2(x, 104), Vector2(x, size.y - 38), Color(0.38, 0.47, 0.38, 0.035))
	for y in range(104, int(size.y) - 38, 28):
		draw_line(Vector2(24, y), Vector2(size.x - 24, y), Color(0.38, 0.47, 0.38, 0.035))

func _panel_style(color: Color, border: Color, padding: int = 16) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style

func _button(text: String, parent: Node, action: Callable, minimum: Vector2 = Vector2(0, 42)) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = minimum
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color("657260"))
	button.add_theme_stylebox_override("normal", _panel_style(Color("26382b"), LINE, 7))
	button.add_theme_stylebox_override("hover", _panel_style(Color("354b38"), GOLD, 7))
	button.add_theme_stylebox_override("pressed", _panel_style(Color("17251e"), GOLD, 7))
	button.add_theme_stylebox_override("focus", _panel_style(Color(0, 0, 0, 0), GOLD, 7))
	button.add_theme_stylebox_override("disabled", _panel_style(Color("1e2c23"), Color("334433"), 7))
	parent.add_child(button)
	button.pressed.connect(action)
	return button

func _label(parent: Node, font_size: int = 16, color: Color = INK) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _space(parent: Node, height: float) -> void:
	var control := Control.new()
	control.custom_minimum_size.y = height
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(control)

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	column.add_child(header)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	title_label = _label(titles, 30)
	subtitle_label = _label(titles, 12, GOLD)
	language_button = _button("EN", header, _toggle_language, Vector2(58, 42))
	language_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sound_button = _button("", header, _toggle_sound, Vector2(94, 42))
	sound_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var rule := HSeparator.new()
	rule.add_theme_color_override("color", LINE)
	column.add_child(rule)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	board = Board.new()
	board.font = FACE
	body.add_child(board)
	board.configuration_changed.connect(_configuration_changed)
	board.busy_changed.connect(_refresh_busy)
	board.flow_finished.connect(_flow_finished)
	board.ring_selected.connect(func(_index: int): _refresh_selection())
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 286
	side.add_theme_constant_override("separation", 8)
	body.add_child(side)
	note_heading = _label(side, 12, GOLD)
	goal_label = _label(side, 23)
	goal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var note_panel := PanelContainer.new()
	note_panel.add_theme_stylebox_override("panel", _panel_style(Color("1c2d23"), LINE, 12))
	side.add_child(note_panel)
	note_label = _label(note_panel, 14, MUTED)
	note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for ring in range(3):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 7)
		side.add_child(row)
		var label := _button("", row, func(): board.select_ring(ring), Vector2(138, 40))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ring_labels.append(label)
		turn_buttons.append(_button("↶", row, func(): board.rotate_ring(ring, -1), Vector2(49, 40)))
		turn_buttons.append(_button("↷", row, func(): board.rotate_ring(ring, 1), Vector2(49, 40)))
	test_button = _button("", side, start_test, Vector2(0, 44))
	test_button.add_theme_stylebox_override("normal", _panel_style(Color("b4c0a5"), Color("c9d1b7"), 10))
	test_button.add_theme_color_override("font_color", Color("17231a"))
	reset_button = _button("", side, reset_puzzle, Vector2(0, 40))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(spacer)
	var status_panel := PanelContainer.new()
	status_panel.custom_minimum_size.y = 94
	status_panel.add_theme_stylebox_override("panel", _panel_style(Color("172820"), LINE, 12))
	side.add_child(status_panel)
	var status_column := VBoxContainer.new()
	status_column.add_theme_constant_override("separation", 8)
	status_panel.add_child(status_column)
	status_heading = _label(status_column, 12, GOLD)
	status_label = _label(status_column, 14, MUTED)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer_label = _label(column, 12, MUTED)
	_refresh_selection()

func _text(zh: String, en: String) -> String:
	return zh if language == "zh" else en

func _refresh_text() -> void:
	title_label.text = _text("汞回路", "Mercury Return")
	subtitle_label.text = _text("朽然 / 闭路校准", "WITHERED STILL / CLOSED-CIRCUIT CALIBRATION")
	note_heading.text = _text("校准手记 / 01", "CALIBRATION NOTE / 01")
	goal_label.text = _text("经过核心，\n回到原处。", "Through the core.\nBack to the source.")
	note_label.text = _text("旋转管环，接通去程与回程。\n部分管道可闲置；交叉处不相通。",
		"Connect outward and return paths.\nSome pipes stay unused. Crossings are separate; match the pipe ends.")
	var names := ["外环", "中环", "内环"] if language == "zh" else ["Outer", "Middle", "Inner"]
	for ring in range(3):
		ring_labels[ring].text = "%d  %s" % [ring + 1, names[ring]]
		turn_buttons[ring * 2].tooltip_text = _text("逆时针转一格", "One step counterclockwise")
		turn_buttons[ring * 2 + 1].tooltip_text = _text("顺时针转一格", "One step clockwise")
	test_button.text = _text("试流", "Test flow")
	reset_button.text = _text("复位 / 重新开始", "Reset puzzle")
	language_button.text = "EN" if language == "zh" else "中文"
	sound_button.text = _text("声音 开" if sound_enabled else "声音 关", "Sound on" if sound_enabled else "Sound off")
	footer_label.text = _text("1 / 2 / 3 选择管环    ← / → 转动    空格 试流    R 复位        ·        无计时，可反复尝试",
		"1 / 2 / 3 Select ring    ← / → Turn    Space Test    R Reset        ·        No timer. Try as often as you like.")
	board.language = language
	board.queue_redraw()
	_refresh_status()

func _refresh_status() -> void:
	status_heading.text = _text("回路状态", "CIRCUIT STATUS")
	status_label.add_theme_color_override("font_color", BLUE if board.circuit_ready else MUTED)
	if board.testing:
		status_label.text = _text("水银试流中…", "Mercury is flowing…")
		return
	match status_kind:
		"initial": status_label.text = _text("回路未就绪。\n试着转动管环，再按「试流」。", "Circuit not ready.\nTurn a ring, then test the flow.")
		"changed": status_label.text = _text("管环已调整。\n可重新试流。", "Rings adjusted.\nReady for another flow test.")
		"success": status_label.text = _text("闭路校准完成。\n水银已通过核心并返回储液罐。", "Calibration complete.\nMercury passed through the core and returned.")
		"outer-gap": status_label.text = _text("水银停在外框封口。\n这里不是回流口。", "Mercury reached a sealed outer port.\nThis is not the return inlet.")
		"core-gap": status_label.text = _text("水银到达核心边缘，\n但没有对准核心接口。", "Mercury reached the core edge,\nbut missed its inlet.")
		"loop": status_label.text = _text("水银困在局部回路中。", "Mercury is trapped in a local loop.")
		"return": status_label.text = _text("水银提前返回，\n还没有经过核心。", "Mercury returned too soon,\nwithout passing through the core.")
		_:
			if board.last_result.get("core", false):
				status_label.text = _text("水银已通过核心，\n但回程仍有断口。", "Mercury passed through the core,\nbut the return path has a gap.")
			else:
				status_label.text = _text("水银停在未接合的管口。\n检查画面中的红色停流点。", "Mercury stopped at a gap.\nLook for the red stop marker.")

func _refresh_selection() -> void:
	for i in range(ring_labels.size()):
		ring_labels[i].add_theme_color_override("font_color", GOLD if i == board.selected_ring else MUTED)

func _refresh_busy() -> void:
	if board.drag_ring >= 0:
		status_kind = "changed"
		readiness_changed.emit(false)
	for button in turn_buttons:
		button.disabled = board.is_busy()
	test_button.disabled = board.is_busy()
	_refresh_status()

func _configuration_changed() -> void:
	status_kind = "changed"
	readiness_changed.emit(false)
	_refresh_status()
	if sound_enabled and tick_player != null:
		tick_player.play()

func start_test() -> void:
	if board.is_busy():
		return
	readiness_changed.emit(false)
	board.start_test()

func reset_puzzle() -> void:
	board.reset_puzzle()
	status_kind = "initial"
	_refresh_status()
	board.grab_focus()

func _flow_finished(success: bool, kind: String) -> void:
	status_kind = "success" if success else kind
	_refresh_status()
	readiness_changed.emit(success)
	if success:
		solved.emit()
		if sound_enabled:
			finish_player.play()

func _toggle_language() -> void:
	language = "en" if language == "zh" else "zh"
	_refresh_text()

func _toggle_sound() -> void:
	sound_enabled = not sound_enabled
	if not sound_enabled:
		tick_player.stop()
		finish_player.stop()
	_refresh_text()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode in [KEY_LEFT, KEY_RIGHT, KEY_SPACE] and not board.has_focus():
		return
	match event.physical_keycode:
		KEY_1, KEY_2, KEY_3:
			board.select_ring(event.physical_keycode - KEY_1)
			board.grab_focus()
		KEY_LEFT: board.rotate_ring(board.selected_ring, -1)
		KEY_RIGHT: board.rotate_ring(board.selected_ring, 1)
		KEY_SPACE: start_test()
		KEY_R: reset_puzzle()
		_: return
	get_viewport().set_input_as_handled()

func _build_audio() -> void:
	tick_player = AudioStreamPlayer.new()
	tick_player.stream = _tone(0.045, 1050.0, 6.0)
	tick_player.volume_db = -24
	add_child(tick_player)
	finish_player = AudioStreamPlayer.new()
	finish_player.stream = _tone(0.48, 440.0, 3.0)
	finish_player.volume_db = -25
	add_child(finish_player)

func _tone(duration: float, frequency: float, decay: float) -> AudioStreamWAV:
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = 22050
	var count := int(duration * wave.mix_rate)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	for i in range(count):
		var t := float(i) / wave.mix_rate
		var attack := minf(t / 0.004, 1.0)
		var envelope := attack * exp(-decay * t / duration) * (1.0 - t / duration)
		var sample := (sin(TAU * frequency * t) + 0.35 * sin(TAU * frequency * 1.5 * t)) * envelope * 16000.0
		bytes.encode_s16(i * 2, int(sample))
	wave.data = bytes
	return wave
