class_name Launcher extends Control

## Launcher
##
## The front door: every world in `worlds/`, and the two things you can do with one —
## **play it** or **edit it**.
##
## It is a WORLD select, not a level select and not a campaign. There are no levels
## (`AGENTS.md` §"the 2026-08-04 consolidation"), and the list here is a list of FILES
## a developer has in the tree: the shipped world, the testbed, and whatever else you
## are trying out. Nothing about the order or the contents of this list means anything
## to the game.
##
## The regions of the selected world are listed too, and picking one starts the run
## there. That is the closest thing this game has to picking a level, and it exists
## for exactly one reason: the beat you are working on is usually not the one the
## world spawns you in.
##
## Built in code rather than as a scene, like `EditorUI` and `WorldHud`, because what
## it shows is generated from the files that happen to be on disk.

## Where a world file lives. Non-recursive on purpose: it is what keeps the suite's
## fixtures (`worlds/fixtures/`) out of a list of things to play, without this file
## having to know they exist. See `worlds/fixtures/README.md`.
const WORLDS_DIR := "res://worlds"

const C_TITLE := Color("cfd6e6")
const C_DIM := Color(0.62, 0.66, 0.76)
const C_OK := Color("7fd6a2")
const C_WARN := Color("e8c07a")
const C_BG := Color(0.055, 0.06, 0.08)

## Play a world: `(source, at)` — a path here, since nothing in this screen has a
## world in memory to hand over. Same signal the editor emits, so `Shell` opens a run
## the one way. See `docs/features/SHELL.md`.
signal play_requested(source, at)
## Edit a world, optionally landing on one of its regions.
signal edit_requested(path, region)
## Nothing under the launcher — the shell reads this as quitting.
signal left

## What is in `worlds/`, as `{"path", "name", "id", "start", "regions", "doors",
## "hands", "problem"}`, sorted by file name. Rebuilt on every entry into the tree
## (see `_enter_tree`), so a world the editor wrote while you were away is current
## when you come back to pick it.
var worlds: Array = []

## Which world is selected, as an index into `worlds`, or -1 when the directory is
## empty. An index, because that is what the list widget speaks — but it is re-found
## BY PATH after a rescan (see `scan`), since a world file appearing in the directory
## would otherwise shift the selection onto its neighbour.
var selected: int = -1

## Which region of the selected world a run would start in, or "" for the world's own
## start region.
var selected_region: String = ""

var _world_list: ItemList
var _region_list: ItemList
var _summary: RichTextLabel
var _play_button: Button
var _edit_button: Button


## Rescanning here rather than in `_ready` is what makes coming back from the editor
## show what the editor just saved: a suspended screen re-enters the tree, and does not
## run `_ready` again. See `Shell`.
func _enter_tree() -> void:
	scan()
	if _world_list != null:
		_fill()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()
	_fill()


# ---------------------------------------------------------------------------
# What is on disk
# ---------------------------------------------------------------------------

## Read every world in `worlds/` into a row for the list.
##
## The whole file is parsed rather than its first few keys, because everything worth
## showing about a world — how many regions, how many doors, where it starts — is only
## knowable by parsing it, and a world that will not parse is the single most useful
## thing this screen can tell you. A world that fails to load keeps its row and wears
## the reason.
func scan() -> void:
	# What you had chosen, by identity rather than by position — a rescan happens every
	# time you come back from playing or editing, and it must not move you somewhere
	# else because a file appeared.
	var keep_path := String(selected_world().get("path", ""))
	var keep_region := selected_region
	var found: Array = []
	for name in FileUtils.json_names_in(WORLDS_DIR + "/"):
		var path := "%s/%s.json" % [WORLDS_DIR, name]
		var data := WorldData.load_from(path)
		if data == null:
			found.append({"path": path, "name": name, "id": name, "start": "",
				"regions": [], "doors": 0, "hands": [], "problem": "will not parse"})
			continue
		var region_ids: Array = data.regions.keys()
		region_ids.sort()
		found.append({
			"path": path, "name": name,
			"id": data.world_name if not data.world_name.is_empty() else name,
			"start": data.start_region, "regions": region_ids,
			"doors": data.doors.size(), "hands": data.starting_hands.duplicate(),
			"problem": "" if data.has_region(data.start_region)
				else "starts in \"%s\", which it has no region for" % data.start_region,
		})
	worlds = found
	selected = _index_of_path(keep_path)
	if selected < 0 and not worlds.is_empty():
		# Opening on the world that ships rather than on whichever one sorts first, so
		# the commonest thing you can want here is one key away.
		selected = maxi(_index_of_path(WorldData.SHIPPED_WORLD), 0)
	# The region survives too, so "play east, die, play east again" is one key — but
	# only if it is still a region of the world it was picked in.
	selected_region = keep_region if regions_here().has(keep_region) else ""


func _index_of_path(path: String) -> int:
	for i in range(worlds.size()):
		if String(worlds[i]["path"]) == path:
			return i
	return -1


func selected_world() -> Dictionary:
	if selected < 0 or selected >= worlds.size():
		return {}
	return worlds[selected]


## The regions of the selected world, sorted. Empty when nothing is selected.
func regions_here() -> Array:
	return selected_world().get("regions", [])


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

## Play the selection, starting in the chosen region if one is chosen.
##
## No cell: a region's own spawn is where its author decided you should arrive, and a
## launcher is not standing anywhere to mean anything more specific. Picking a cell is
## the editor's gesture, because that is where you can see the cells.
func play() -> void:
	var world := selected_world()
	if world.is_empty():
		return
	var at := {} if selected_region.is_empty() else {"region": selected_region}
	play_requested.emit(String(world["path"]), at)


func edit() -> void:
	var world := selected_world()
	if world.is_empty():
		return
	edit_requested.emit(String(world["path"]), selected_region)


func select(index: int) -> void:
	if index < 0 or index >= worlds.size() or index == selected:
		return
	selected = index
	selected_region = ""
	_fill()


## Choose which region a run starts in. Choosing the one already chosen clears it,
## which is the only way back to "wherever the world says" once you have picked.
func select_region(id: String) -> void:
	selected_region = "" if id == selected_region else id
	_fill()


# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------
# The lists own the arrow keys, which is what makes this navigable without a mouse.
# Everything else is a verb.

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_ENTER, KEY_KP_ENTER:
			play()
		KEY_E:
			edit()
		# The same key that plays from inside the editor, so the one gesture works
		# wherever you are when you decide to look at the world.
		KEY_F5:
			play()
		KEY_ESCAPE:
			left.emit()
		_:
			return
	get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------
# Presentation
# ---------------------------------------------------------------------------

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	var title := Label.new()
	title.text = "Space Folding"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", C_TITLE)
	col.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "%s — pick a world to play or edit" % WORLDS_DIR
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", C_DIM)
	col.add_child(subtitle)

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 18)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(split)

	_world_list = _list(340)
	_world_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_world_list.item_selected.connect(select)
	_world_list.item_activated.connect(func(i: int):
		select(i)
		play())
	split.add_child(_world_list)

	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 10)
	split.add_child(detail)

	_summary = RichTextLabel.new()
	_summary.bbcode_enabled = true
	_summary.fit_content = true
	_summary.scroll_active = false
	_summary.custom_minimum_size = Vector2(0, 86)
	detail.add_child(_summary)

	var regions_head := Label.new()
	regions_head.text = "REGIONS — pick one to start there"
	regions_head.add_theme_font_size_override("font_size", 11)
	regions_head.add_theme_color_override("font_color", C_DIM)
	detail.add_child(regions_head)

	_region_list = _list(0)
	_region_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_region_list.item_selected.connect(func(i: int):
		select_region(_region_list.get_item_metadata(i)))
	_region_list.item_activated.connect(func(i: int):
		selected_region = _region_list.get_item_metadata(i)
		play())
	detail.add_child(_region_list)

	var buttons := HBoxContainer.new()
	detail.add_child(buttons)
	_play_button = Button.new()
	_play_button.pressed.connect(play)
	buttons.add_child(_play_button)
	_edit_button = Button.new()
	_edit_button.pressed.connect(edit)
	buttons.add_child(_edit_button)
	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func(): left.emit())
	buttons.add_child(quit)

	var hint := Label.new()
	hint.text = "⏎ play · E edit · ↑↓ choose · Esc quit" \
		+ "   ·   the editor plays what you are editing with F5, and F6 from the cursor"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", C_DIM)
	col.add_child(hint)


## A list that does not eat letters. `allow_search` turns typing into a jump-to-item,
## which would swallow `E` — the one key this screen most needs to hear.
func _list(width: int) -> ItemList:
	var list := ItemList.new()
	list.allow_search = false
	list.custom_minimum_size = Vector2(width, 0)
	list.add_theme_color_override("font_color", C_TITLE)
	return list


func _fill() -> void:
	if _world_list == null:
		return
	_world_list.clear()
	for i in range(worlds.size()):
		var world: Dictionary = worlds[i]
		_world_list.add_item("%s   (%d regions)"
			% [String(world["name"]), (world["regions"] as Array).size()])
		if not String(world["problem"]).is_empty():
			_world_list.set_item_custom_fg_color(i, C_WARN)
		_world_list.set_item_tooltip(i, String(world["path"]))
		if i == selected:
			_world_list.select(i)

	var chosen := selected_world()
	_summary.text = _summary_text(chosen)

	_region_list.clear()
	for id in regions_here():
		var rid := String(id)
		var i := _region_list.add_item(
			"%s%s" % [rid, "   ← the world starts here" if rid == chosen.get("start", "") else ""])
		_region_list.set_item_metadata(i, rid)
		if rid == chosen.get("start", ""):
			_region_list.set_item_custom_fg_color(i, C_OK)
		if rid == selected_region:
			_region_list.select(i)

	var target := selected_region if not selected_region.is_empty() \
		else String(chosen.get("start", ""))
	_play_button.disabled = chosen.is_empty()
	_edit_button.disabled = chosen.is_empty()
	_play_button.text = "▶ Play  (⏎)" if target.is_empty() else "▶ Play %s  (⏎)" % target
	_edit_button.text = "✎ Edit  (E)"


func _summary_text(world: Dictionary) -> String:
	if world.is_empty():
		return "[color=#%s]nothing in %s to open[/color]" % [C_WARN.to_html(false), WORLDS_DIR]
	var dim := "#" + C_DIM.to_html(false)
	var lines: Array = []
	lines.append("[font_size=20]%s[/font_size]" % String(world["id"]))
	lines.append("[color=%s]%s[/color]" % [dim, String(world["path"])])
	lines.append("[color=%s]%d regions · %d doors · starts in %s · hands: %s[/color]"
		% [dim, (world["regions"] as Array).size(), int(world["doors"]),
			String(world["start"]) if not String(world["start"]).is_empty() else "—",
			", ".join(world["hands"]) if not (world["hands"] as Array).is_empty() else "none"])
	if not String(world["problem"]).is_empty():
		lines.append("[color=#%s]%s[/color]" % [C_WARN.to_html(false), String(world["problem"])])
	return "\n".join(lines)
