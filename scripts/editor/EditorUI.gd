class_name EditorUI extends CanvasLayer

## EditorUI
##
## The editor's panel: tools, the tile palette, the canvas list, and the running
## report of what is wrong with the world.
##
## Built in code rather than as a scene, like `FoldWorld._build_hud` — the palette
## and the hand kinds are generated from their REGISTRIES, so half of this panel
## could not be laid out in the Godot editor without being wrong the next time a
## tile type is added. A `.tscn` would freeze a copy of `TileTypes`.
##
## Everything here is presentation and dispatch: a widget reads `editor.doc` to
## show state and calls a command on `WorldEditor` to change it. No mutation
## happens in this file.

## Colours come from `EditorBoard`, which owns the editor's whole palette — see
## the note there for why they live in the file that draws rather than the file
## that reports.
const C_OK := EditorBoard.C_OK
const C_WARN := EditorBoard.C_WARN
const C_BAD := EditorBoard.C_BAD
const C_DIM := EditorBoard.C_DIM

const PANEL_W := 292
const INSPECTOR_W := 236
const TOAST_SECONDS := 4.0

var editor = null

var _panel: PanelContainer
var _status_bar: VBoxContainer
var _path_label: Label
var _summary: Label
var _tool_buttons: Dictionary = {}     # Tool -> Button
var _tile_buttons: Dictionary = {}     # char -> Button
var _hand_pick: OptionButton
var _region_list: ItemList
var _new_name: LineEdit
var _new_w: SpinBox
var _new_h: SpinBox
var _sel_name: LineEdit
var _sel_w: SpinBox
var _sel_h: SpinBox
var _sel_box: VBoxContainer
var _inspector: PanelContainer
var _tile_box: VBoxContainer
var _tile_head: Label
var _tile_form: VBoxContainer
var _issues: RichTextLabel

## Signature of the tile form currently built, so `refresh()` — which runs on
## every press — rebuilds the widgets only when the form's SHAPE changes. A
## rebuild on every refresh would take focus out of the field being typed in
## after each keystroke.
var _tile_form_key: String = ""

## The generated parameter widgets, as `{"key", "kind", "node", "index"}`, so
## values can be pushed into them without rebuilding. See `_sync_tile_form`.
var _param_rows: Array = []
var _hint: Label
var _toast: Label
var _toast_left: float = 0.0


func _ready() -> void:
	layer = 10
	_build()
	set_process(true)


func _process(delta: float) -> void:
	if _toast_left <= 0.0:
		return
	_toast_left -= delta
	_toast.modulate.a = clampf(_toast_left / 1.2, 0.0, 1.0)


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

## How much of the window this panel covers. `WorldEditor` frames the board into
## what is LEFT of the window, so a "frame all" does not tuck a card underneath
## here. A method rather than a constant read from outside, so that file never has
## to name this one — see the dependency note in `WorldEditor._ready`.
##
## It reports the MEASURED width, not `PANEL_W`: a container grows past its
## minimum to fit its contents, and a long tile name would otherwise push the
## panel out over a board that still thought it had the room.
func panel_width() -> float:
	if _panel == null or _panel.size.x <= 0.0:
		return float(PANEL_W)
	return _panel.size.x


func _build() -> void:
	var panel := PanelContainer.new()
	_panel = panel
	panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	panel.custom_minimum_size = Vector2(PANEL_W, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# The default theme's panel is translucent, which over a board of terrain
	# reads as a rendering bug rather than a panel.
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.09, 0.10, 0.13)
	bg.border_color = Color(0.20, 0.22, 0.28)
	bg.border_width_right = 1
	bg.content_margin_left = 10
	bg.content_margin_right = 10
	bg.content_margin_top = 10
	bg.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", bg)
	add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(PANEL_W - 24, 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	scroll.add_child(col)

	_build_file(col)
	_build_tools(col)
	_build_palette(col)
	_build_canvases(col)
	_build_issues(col)
	_build_inspector()
	_build_status()


func _heading(parent: Control, text: String) -> void:
	var sep := HSeparator.new()
	parent.add_child(sep)
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override("font_size", 11)
	label.modulate = C_DIM
	parent.add_child(label)


func _build_file(col: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "World Editor"
	title.add_theme_font_size_override("font_size", 18)
	col.add_child(title)

	_path_label = Label.new()
	_path_label.add_theme_font_size_override("font_size", 11)
	_path_label.modulate = C_DIM
	_path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_path_label)

	# The problem COUNT rides at the top, where it is always visible; the list
	# itself is at the bottom of a panel that scrolls. "Your world is broken" is
	# not something to find only by scrolling for it.
	_summary = Label.new()
	_summary.add_theme_font_size_override("font_size", 11)
	col.add_child(_summary)

	var row := HBoxContainer.new()
	col.add_child(row)
	_button(row, "Save", func(): editor.save())
	_button(row, "Reload", func(): editor.reload())
	_button(row, "Frame all", func(): editor.frame_all())


func _build_tools(col: VBoxContainer) -> void:
	_heading(col, "Tools")
	var grid := GridContainer.new()
	grid.columns = 2
	col.add_child(grid)
	var group := ButtonGroup.new()
	# Ordered as they are used, not as the enum happens to be declared.
	for entry in [
		[WorldEditor.Tool.PAINT, "Paint (B)"], [WorldEditor.Tool.RECT, "Rect (E)"],
		[WorldEditor.Tool.PICK, "Pick (I)"], [WorldEditor.Tool.SPAWN, "Spawn (P)"],
		[WorldEditor.Tool.DOOR, "Door (D)"], [WorldEditor.Tool.FOLD, "Fold anchor (A)"],
		[WorldEditor.Tool.ANCHOR, "World anchor (W)"],
		[WorldEditor.Tool.LIGHT, "Light (L)"], [WorldEditor.Tool.HAND, "Hand (H)"],
		[WorldEditor.Tool.TILE, "Tile data (T)"],
	]:
		var tool: int = entry[0]
		var b := Button.new()
		b.text = String(entry[1])
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func(): editor.set_tool(tool))
		grid.add_child(b)
		_tool_buttons[tool] = b


## The tile palette, generated from `EditorTools.palette()` — which is itself
## derived from `WorldCore.CHARS` and `TileTypes`. Register a tile type and it
## appears here; there is no list to update.
func _build_palette(col: VBoxContainer) -> void:
	_heading(col, "Tiles")
	var grid := GridContainer.new()
	grid.columns = 2
	col.add_child(grid)
	var group := ButtonGroup.new()
	var index := 1
	for entry in EditorTools.palette():
		var ch := String(entry["char"])
		var b := Button.new()
		b.text = "%d  %s  %s" % [index, ch, String(entry["name"])]
		b.tooltip_text = "%s — paints '%s'" % [String(entry["name"]), ch]
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		# A long registry name must not widen the whole panel; the tooltip carries
		# the full text.
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 12)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_color_override("font_color", TileAtlas.base_color(int(entry["type"])).lightened(0.35))
		b.pressed.connect(func(): editor.set_brush(ch))
		grid.add_child(b)
		_tile_buttons[ch] = b
		index += 1

	var row := HBoxContainer.new()
	col.add_child(row)
	var label := Label.new()
	label.text = "Hand kind"
	row.add_child(label)
	_hand_pick = OptionButton.new()
	_hand_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for kind in HandTypes.all_types():
		_hand_pick.add_item(HandTypes.type_name(int(kind)), int(kind))
	_hand_pick.item_selected.connect(func(i: int):
		editor.hand_kind = _hand_pick.get_item_id(i))
	row.add_child(_hand_pick)


func _build_canvases(col: VBoxContainer) -> void:
	_heading(col, "Canvases")
	_region_list = ItemList.new()
	_region_list.custom_minimum_size = Vector2(0, 84)
	_region_list.item_selected.connect(func(i: int):
		editor.select_region(_region_list.get_item_text(i)))
	_region_list.item_activated.connect(func(i: int):
		editor.focus_region(_region_list.get_item_text(i)))
	col.add_child(_region_list)

	var make := HBoxContainer.new()
	col.add_child(make)
	_new_name = LineEdit.new()
	_new_name.placeholder_text = "name"
	_new_name.tooltip_text = "name for a new canvas — left blank, one is generated"
	_new_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	make.add_child(_new_name)
	_new_w = _spin(make, 32)
	_new_h = _spin(make, 18)
	_button(make, "+", func():
		var id := _new_name.text.strip_edges()
		if id == "":
			id = "region_%d" % (editor.doc.region_ids().size() + 1)
		editor.new_region(id, Vector2i(int(_new_w.value), int(_new_h.value)))
		_new_name.text = "")

	_sel_box = VBoxContainer.new()
	_sel_box.add_theme_constant_override("separation", 4)
	col.add_child(_sel_box)

	var name_row := HBoxContainer.new()
	_sel_box.add_child(name_row)
	_sel_name = LineEdit.new()
	_sel_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sel_name.tooltip_text = "rename this canvas (enter)"
	_sel_name.text_submitted.connect(func(text: String):
		editor.rename_region(editor.selected_region, text.strip_edges()))
	name_row.add_child(_sel_name)

	var size_row := HBoxContainer.new()
	_sel_box.add_child(size_row)
	var size_label := Label.new()
	size_label.text = "size"
	size_row.add_child(size_label)
	_sel_w = _spin(size_row, 32)
	_sel_h = _spin(size_row, 18)
	_button(size_row, "Apply", func():
		editor.resize_selected(Vector2i(int(_sel_w.value), int(_sel_h.value))))

	var act_row := HBoxContainer.new()
	_sel_box.add_child(act_row)
	_button(act_row, "Set start", func(): editor.set_start_region(editor.selected_region))
	_button(act_row, "Delete", func(): editor.delete_region(editor.selected_region))


## The tile inspector: its own panel on the RIGHT, not another section of the
## left one.
##
## Two reasons. It is the panel you are actively working in while clicking cells,
## and a section at the bottom of a column that already scrolls would be below
## the fold exactly when it is in use. And it appears only when there is a tile
## to show, so the board keeps the whole window the rest of the time.
##
## Its CONTENTS are generated per selected tile from `TileTypes`' `params`
## schema — see `_rebuild_tile_form`. There is deliberately nothing
## trigger-shaped here: this panel has never heard of a channel.
func _build_inspector() -> void:
	_inspector = PanelContainer.new()
	_inspector.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_inspector.custom_minimum_size = Vector2(INSPECTOR_W, 0)
	_inspector.offset_left = -INSPECTOR_W
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.09, 0.10, 0.13)
	bg.border_color = Color(0.20, 0.22, 0.28)
	bg.border_width_left = 1
	bg.content_margin_left = 10
	bg.content_margin_right = 10
	bg.content_margin_top = 10
	bg.content_margin_bottom = 10
	_inspector.add_theme_stylebox_override("panel", bg)
	add_child(_inspector)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_inspector.add_child(scroll)

	_tile_box = VBoxContainer.new()
	_tile_box.custom_minimum_size = Vector2(INSPECTOR_W - 24, 0)
	_tile_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tile_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_tile_box)

	var title := Label.new()
	title.text = "TILE DATA"
	title.add_theme_font_size_override("font_size", 11)
	title.modulate = C_DIM
	_tile_box.add_child(title)

	_tile_head = Label.new()
	_tile_head.add_theme_font_size_override("font_size", 12)
	_tile_head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tile_box.add_child(_tile_head)

	_tile_form = VBoxContainer.new()
	_tile_form.add_theme_constant_override("separation", 4)
	_tile_box.add_child(_tile_form)


## How much of the window the inspector covers — zero while it is hidden. Same
## contract as `panel_width`, and `WorldEditor.free_rect` subtracts both.
func inspector_width() -> float:
	if _inspector == null or not _inspector.visible:
		return 0.0
	return maxf(_inspector.size.x, INSPECTOR_W)


## Build the form for the selected tile, one row per declared parameter.
##
## This is the uniform part: the widget comes from the parameter's `type`, the
## label and tooltip from its `label` and `hint`, and the write-back is
## `editor.set_tile_param(key, value)` for every one of them. Declaring a
## parameter in `TileTypes` is the whole job — no branch here names a tile type.
##
## Building is separate from FILLING (`_sync_tile_form`) because the two happen
## at different rates: the widgets change only when a different tile is selected,
## while their values change on every edit. Rebuilding to show a new value would
## free the field being typed in.
func _rebuild_tile_form(doc: EditorDoc) -> void:
	# `queue_free` without `remove_child`: a rebuild is usually running inside a
	# signal handler of one of these very buttons, so they cannot be freed now —
	# and detaching them first would leave them parentless until the frame ends,
	# which is the definition of an orphan. They stay put and die at end of frame;
	# a second rebuild before then skips the ones already on their way out.
	for child in _tile_form.get_children():
		if not child.is_queued_for_deletion():
			child.queue_free()
	_param_rows = []
	var target: Dictionary = editor.inspected()
	if target.is_empty():
		_tile_head.text = "no tile selected — take the Tile tool (T) and click one"
		_tile_head.modulate = C_DIM
		return

	var type: int = target["type"]
	var cell: Vector2i = target["cell"]
	_tile_head.text = "%s at %d,%d" % [TileTypes.type_name(type), cell.x, cell.y]
	_tile_head.modulate = Color.WHITE
	if not TileParams.has_params(type):
		_tile_head.text += " — nothing to configure"
		_tile_head.modulate = C_DIM
		return

	for spec in TileParams.specs_for(type):
		_add_param_row(spec)

	var clear := Button.new()
	clear.text = "Clear settings"
	clear.tooltip_text = "remove this tile's entry from the world file entirely"
	clear.pressed.connect(func(): editor.clear_tile_data())
	_tile_form.add_child(clear)
	_sync_tile_form(doc)


## One parameter: a label, then whatever widget its declared type calls for.
func _add_param_row(spec: Dictionary) -> void:
	var key := String(spec["key"])
	var hint := String(spec.get("hint", ""))
	var label := Label.new()
	label.text = String(spec.get("label", key))
	label.add_theme_font_size_override("font_size", 11)
	label.modulate = C_DIM
	label.tooltip_text = hint
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tile_form.add_child(label)

	match String(spec.get("type", TileParams.STRING)):
		TileParams.CELLS:
			_add_cells_rows(spec)
		TileParams.BOOL:
			var check := CheckBox.new()
			check.tooltip_text = hint
			check.toggled.connect(func(on: bool): editor.set_tile_param(key, on))
			_tile_form.add_child(check)
			_param_rows.append({"key": key, "kind": TileParams.BOOL, "node": check})
		TileParams.INT, TileParams.FLOAT:
			var spin := SpinBox.new()
			spin.allow_greater = true
			spin.allow_lesser = true
			spin.step = 1.0 if String(spec["type"]) == TileParams.INT else 0.1
			spin.tooltip_text = hint
			spin.value_changed.connect(func(v: float): editor.set_tile_param(key, v))
			_tile_form.add_child(spin)
			_param_rows.append({"key": key, "kind": String(spec["type"]), "node": spin})
		_:
			var edit := LineEdit.new()
			edit.tooltip_text = hint
			# Written on every keystroke under a coalescing tag, so the value is
			# never left uncommitted in a widget — clicking away from a
			# half-typed field must not discard it — while the whole typing
			# session still costs exactly one undo.
			edit.text_changed.connect(func(text: String): editor.set_tile_param(key, text, false))
			edit.text_submitted.connect(func(_text: String): editor.commit_tile_param())
			edit.focus_exited.connect(func(): editor.commit_tile_param())
			_tile_form.add_child(edit)
			_param_rows.append({"key": key, "kind": TileParams.STRING, "node": edit})


## One row per slot of a `cells` parameter: what it points at, a button that arms
## a board click to change it, and a button that unsets it. Picking on the board
## rather than typing coordinates is the point — these are base cells, and nobody
## can read a fold out of two integers.
func _add_cells_rows(spec: Dictionary) -> void:
	var key := String(spec["key"])
	for i in range(maxi(int(spec.get("count", 1)), 1)):
		var index := i
		var row := HBoxContainer.new()
		_tile_form.add_child(row)

		var slot := Label.new()
		slot.text = "%d" % (i + 1)
		slot.custom_minimum_size = Vector2(12, 0)
		slot.add_theme_font_size_override("font_size", 11)
		slot.modulate = C_DIM
		row.add_child(slot)

		var pick := Button.new()
		pick.tooltip_text = "pick this cell on the board"
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pick.clip_text = true
		pick.pressed.connect(func(): editor.begin_pick(key, index))
		row.add_child(pick)

		var clear := Button.new()
		clear.text = "×"
		clear.tooltip_text = "unset this cell"
		clear.pressed.connect(func(): editor.unset_tile_cell(key, index))
		row.add_child(clear)

		_param_rows.append({"key": key, "kind": TileParams.CELLS,
			"node": pick, "index": index})


## Push the stored values into the built widgets.
##
## A widget that currently has KEYBOARD FOCUS is skipped: it already shows what
## the user is typing, and writing the committed value back into it mid-word
## would fight them for the caret.
func _sync_tile_form(doc: EditorDoc) -> void:
	var target: Dictionary = editor.inspected()
	if target.is_empty() or _param_rows.is_empty():
		return
	var data := doc.tile_data(String(target["region"]), target["cell"])
	for row in _param_rows:
		var key := String(row["key"])
		var node: Control = row["node"]
		var value = data.get(key, null)
		match String(row["kind"]):
			TileParams.CELLS:
				var index := int(row["index"])
				var cells: Array = value if value is Array else []
				var cell: Vector2i = cells[index] if index < cells.size() else TileParams.UNSET
				var armed: bool = String(editor.picking.get("key", "")) == key \
					and int(editor.picking.get("index", -1)) == index
				var button := node as Button
				button.text = "click a cell…" if armed else \
					("not set" if cell == TileParams.UNSET else "%d,%d" % [cell.x, cell.y])
				button.add_theme_color_override("font_color",
					C_WARN if armed else (C_DIM if cell == TileParams.UNSET else C_OK))
			TileParams.BOOL:
				(node as CheckBox).button_pressed = bool(value)
			TileParams.INT, TileParams.FLOAT:
				if not (node as SpinBox).get_line_edit().has_focus():
					(node as SpinBox).value = float(value)
			_:
				if not node.has_focus():
					(node as LineEdit).text = str(value)


func _build_issues(col: VBoxContainer) -> void:
	_heading(col, "Problems")
	_issues = RichTextLabel.new()
	_issues.bbcode_enabled = true
	_issues.fit_content = true
	_issues.custom_minimum_size = Vector2(0, 90)
	_issues.add_theme_font_size_override("normal_font_size", 11)
	col.add_child(_issues)


## The bottom strip: what the current tool does, and the last thing that happened.
func _build_status() -> void:
	var bar := VBoxContainer.new()
	_status_bar = bar
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = PANEL_W + 12
	bar.offset_top = -46
	bar.offset_bottom = -8
	bar.offset_right = -12
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)

	_toast = Label.new()
	_toast.add_theme_font_size_override("font_size", 13)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_toast)

	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 11)
	_hint.modulate = C_DIM
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_hint)


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _spin(parent: Control, value: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = WorldEditor.MIN_CELLS
	s.max_value = WorldEditor.MAX_CELLS
	s.value = value
	s.custom_minimum_size = Vector2(52, 0)
	parent.add_child(s)
	return s


# ---------------------------------------------------------------------------
# State -> widgets
# ---------------------------------------------------------------------------

func refresh() -> void:
	if editor == null or editor.doc == null or _path_label == null:
		return
	var doc: EditorDoc = editor.doc
	_status_bar.offset_left = panel_width() + 12.0
	_status_bar.offset_right = -(inspector_width() + 12.0)
	_path_label.text = "%s%s" % [doc.path, "  •unsaved" if doc.dirty else ""]
	_path_label.modulate = C_WARN if doc.dirty else C_DIM

	for tool in _tool_buttons:
		(_tool_buttons[tool] as Button).button_pressed = (editor.tool == tool)
	for ch in _tile_buttons:
		(_tile_buttons[ch] as Button).button_pressed = (editor.brush == ch)
	for i in range(_hand_pick.item_count):
		if _hand_pick.get_item_id(i) == editor.hand_kind:
			_hand_pick.select(i)

	_region_list.clear()
	for id in doc.region_ids():
		var rid := String(id)
		var i := _region_list.add_item(rid)
		if doc.world.start_region == rid:
			_region_list.set_item_custom_fg_color(i, C_OK)
			_region_list.set_item_tooltip(i, "the world starts here")
		if rid == editor.selected_region:
			_region_list.select(i)

	var has: bool = editor.selected_region != "" and doc.has_region(editor.selected_region)
	_sel_box.visible = has
	if has:
		var size := doc.size_of(editor.selected_region)
		_sel_name.text = editor.selected_region
		_sel_w.value = size.x
		_sel_h.value = size.y

	_refresh_tile(doc)
	_refresh_issues(doc)
	var navigation := "wheel zoom · middle/space-drag pan · drag a title bar to move a canvas" \
		+ " · drag a corner to resize · ctrl+z undo · ctrl+s save · home frame all"
	_hint.text = "%s  ·  %s" % [String(WorldEditor.TOOL_HINT.get(editor.tool, "")), navigation]


## Rebuild the tile form only when its SHAPE changes — a different tile, a
## different type, or a pick being armed or finished. `refresh()` runs on every
## mouse press, and rebuilding the widgets each time would yank focus out of the
## field you were typing in and drop the keystroke.
##
## The stored VALUES are not part of the key on purpose: a field the user is
## editing already shows what they typed, and rewriting it under them is exactly
## the loop this guard exists to avoid. The board is what reflects a committed
## value back.
func _refresh_tile(doc: EditorDoc) -> void:
	var target: Dictionary = editor.inspected()
	# Shown when there is a tile to show, and also whenever the Tile tool is in
	# hand — so taking the tool is itself the thing that reveals the panel you are
	# about to use, rather than a click into apparent nothing.
	_inspector.visible = not target.is_empty() or editor.tool == WorldEditor.Tool.TILE
	var key := "-"
	if not target.is_empty():
		key = "%s|%s|%d|%s|%d" % [
			String(target["region"]), target["cell"], int(target["type"]),
			String(editor.picking.get("key", "")), int(editor.picking.get("index", -1))]
	if key == _tile_form_key:
		_sync_tile_form(doc)
		return
	_tile_form_key = key
	_rebuild_tile_form(doc)


func _refresh_issues(doc: EditorDoc) -> void:
	var issues := doc.validate()
	var errors := 0
	for issue in issues:
		if issue["severity"] == "error":
			errors += 1
	var warnings := issues.size() - errors
	if issues.is_empty():
		_summary.text = "no problems"
		_summary.modulate = C_OK
		_issues.text = "[color=#8ce89e]nothing to fix[/color]"
		return
	_summary.text = "%d error(s) · %d warning(s)" % [errors, warnings]
	_summary.modulate = C_BAD if errors > 0 else C_WARN

	var lines: Array = []
	for issue in issues:
		var bad: bool = issue["severity"] == "error"
		var where := "" if issue["region"] == "" else "%s: " % issue["region"]
		lines.append("[color=%s]%s[/color] %s%s" % [
			C_BAD.to_html(false) if bad else C_WARN.to_html(false),
			"✕" if bad else "!", where, issue["message"]])
	_issues.text = "\n".join(lines)


func toast(text: String, color: Color = Color.WHITE) -> void:
	if _toast == null:
		return
	_toast.text = text
	_toast.modulate = color
	_toast.modulate.a = 1.0
	_toast_left = TOAST_SECONDS
