class_name TileParams extends RefCounted

## TileParams
##
## What a tile's per-instance parameters MEAN.
##
## `TileTypes` declares the schema (`params`); this file is everything done with
## it — defaults, reading a stored value, coercing an edited one, deciding what
## is worth writing to the file, and saying what is wrong. The editor's tile
## inspector is generated from these functions and knows nothing about triggers.
##
## The split is the same one as everywhere else in this codebase: the registry
## stays a pure const data table with no outbound references, so the schema uses
## plain strings for its types and this file is the single place that knows what
## `"cells"` is. **Declaring a parameter on a tile type is therefore the whole
## job** — it becomes editable, validated, drawn on the board and saved, without
## the editor or the loader learning a new name.
##
## ## The value types
##
## | `type`   | stored as | edited as |
## |---|---|---|
## | `string` | String | a text field |
## | `int`    | int (JSON number) | a spinner |
## | `float`  | float | a spinner |
## | `bool`   | bool | a checkbox |
## | `cells`  | `[[x, y], ...]` | a list of cell pickers you click on the board |
##
## `cells` carries `count` (how many the type wants) and is the interesting one:
## the coordinates are BASE cells of the region, which is what lets the editor
## draw a line from a trigger to the fold it will make.
##
## ## Two rules about storage
##
## **Only non-default values are written.** A freshly painted trigger stores
## nothing at all, so painting a hundred of them does not put a hundred empty
## dictionaries in the world file. `normalize` is what fills the defaults back in
## for anything that wants a complete picture.
##
## **Unknown keys are kept.** A key this build does not have a spec for is data
## somebody meant, whether it came from a newer version or a hand edit — dropping
## it would make opening a file in the editor a lossy operation. `test_tile_params`
## pins that in both directions.

## The value types a parameter may declare. Names, not ints, because they appear
## verbatim in `TileTypes`' table.
const STRING := "string"
const INT := "int"
const FLOAT := "float"
const BOOL := "bool"
const CELLS := "cells"

## A cell that has been declared but not yet chosen. `cells` entries are padded
## out to `count` with this so the inspector always shows the right number of
## slots and validation can tell "not filled in" from "filled in wrongly".
const UNSET := Vector2i(-1, -1)


# ---------------------------------------------------------------------------
# The schema
# ---------------------------------------------------------------------------

static func specs_for(type: int) -> Array:
	return TileTypes.params(type)


static func has_params(type: int) -> bool:
	return not specs_for(type).is_empty()


## The spec for one key, or `{}`.
static func spec_of(type: int, key: String) -> Dictionary:
	for spec in specs_for(type):
		if String(spec.get("key", "")) == key:
			return spec
	return {}


## Every tile type that takes parameters at all — for tests, and for a UI that
## wants to say which tiles are configurable.
static func types_with_params() -> Array:
	var out: Array = []
	for type in TileTypes.all_types():
		if has_params(int(type)):
			out.append(int(type))
	return out


# ---------------------------------------------------------------------------
# Values
# ---------------------------------------------------------------------------

## The default value of one parameter, as a fresh copy — a `cells` default is an
## Array, and handing out the registry's own instance would let a caller edit the
## const table through it.
static func default_of(spec: Dictionary):
	var kind := String(spec.get("type", STRING))
	if kind == CELLS:
		return _pad_cells([], int(spec.get("count", 0)))
	var value = spec.get("default", _zero_of(kind))
	return value


## A complete parameter dictionary for a type: every declared key at its default.
static func defaults_for(type: int) -> Dictionary:
	var out: Dictionary = {}
	for spec in specs_for(type):
		out[String(spec["key"])] = default_of(spec)
	return out


## Read one parameter out of stored data, coerced and defaulted. This is the only
## function anything should use to ask "what is this tile's channel" — it makes a
## missing key, a key of the wrong JSON type and a hand-edited one all behave.
static func get_value(type: int, data: Dictionary, key: String):
	var spec := spec_of(type, key)
	if spec.is_empty():
		return data.get(key, null)
	if not data.has(key):
		return default_of(spec)
	return coerce(spec, data[key])


## A complete, canonical view of a tile's parameters: every declared key present
## and coerced, plus any unknown keys carried through untouched.
static func normalize(type: int, data: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for spec in specs_for(type):
		var key := String(spec["key"])
		out[key] = coerce(spec, data[key]) if data.has(key) else default_of(spec)
	for key in data:
		if not out.has(key):
			out[key] = data[key]
	return out


## Force a value into the shape its spec declares. Never fails: a value that
## cannot be read lands on the default, because a world file is hand-editable and
## a typo in one field must not stop the region loading.
static func coerce(spec: Dictionary, value):
	match String(spec.get("type", STRING)):
		INT:
			return int(value) if _is_number(value) else int(default_of(spec))
		FLOAT:
			return float(value) if _is_number(value) else float(default_of(spec))
		BOOL:
			return bool(value)
		CELLS:
			return _pad_cells(value, int(spec.get("count", 0)))
		_:
			# `str`, not `String`: the String constructor rejects a plain int,
			# and a hand-edited file can easily hold `"channel": 3`.
			return str(value)


## The value to WRITE for a parameter, or `null` to mean "store nothing". A value
## equal to its default is not worth a line in the file — see the storage note in
## the header.
static func to_stored(spec: Dictionary, value):
	var canonical = coerce(spec, value)
	if _same(canonical, default_of(spec)):
		return null
	if String(spec.get("type", STRING)) == CELLS:
		var out: Array = []
		for cell in canonical:
			out.append([(cell as Vector2i).x, (cell as Vector2i).y])
		return out
	return canonical


## Strip a data dictionary down to what is worth saving: declared keys that differ
## from their default, plus every unknown key. An empty result means the tile has
## nothing to say and its entry can be dropped entirely.
static func to_storage(type: int, data: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for spec in specs_for(type):
		var key := String(spec["key"])
		if not data.has(key):
			continue
		var stored = to_stored(spec, data[key])
		if stored != null:
			out[key] = stored
	for key in data:
		if spec_of(type, String(key)).is_empty():
			out[key] = data[key]
	return out


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

## What is wrong with one tile's parameters, as plain sentences.
##
## `grid_size` bounds-checks `cells` values; pass `Vector2i.ZERO` to skip that.
## Everything here is advisory — the runtime already refuses to act on a
## half-configured tile (`FoldWorld._fire_fold_trigger` pins nothing when
## the anchors are missing), so an unfinished trigger is a thing you are allowed
## to leave on the canvas overnight. The editor's job is to make sure you know.
static func issues(type: int, data: Dictionary, grid_size: Vector2i = Vector2i.ZERO) -> Array:
	var out: Array = []
	var full := normalize(type, data)
	for spec in specs_for(type):
		var key := String(spec["key"])
		var label := String(spec.get("label", key))
		var value = full[key]
		if String(spec.get("type", STRING)) == CELLS:
			var wanted := int(spec.get("count", 0))
			var missing := 0
			for cell in value:
				if cell == UNSET:
					missing += 1
				elif grid_size != Vector2i.ZERO and not _in_bounds(cell, grid_size):
					out.append("%s: %s is outside the region" % [label, cell])
			if missing > 0:
				out.append("%s: %d of %d not chosen" % [label, missing, wanted])
			if _has_duplicate(value):
				out.append("%s: the same cell twice — a fold needs two distinct anchors" % label)
		elif bool(spec.get("required", false)) and _same(value, default_of(spec)):
			out.append("%s is not set" % label)
	return out


## Does this tile have everything it needs to actually do something?
static func is_complete(type: int, data: Dictionary, grid_size: Vector2i = Vector2i.ZERO) -> bool:
	return issues(type, data, grid_size).is_empty()


# ---------------------------------------------------------------------------
# `tile_data` keys
# ---------------------------------------------------------------------------

## A region's `tile_data` is keyed "x,y". These two are the only places that
## spelling should appear outside `WorldData`.
static func key_of(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]


static func cell_of_key(key: String) -> Vector2i:
	var parts := key.split(",")
	if parts.size() != 2:
		return UNSET
	return Vector2i(int(parts[0]), int(parts[1]))


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------

## Read a stored `[[x,y], ...]` (or an already-typed Array of Vector2i) into
## exactly `count` cells, padding with UNSET and truncating the excess.
##
## Padding rather than trusting the length is what lets the inspector show a fixed
## number of slots and lets validation say "1 of 2 not chosen" instead of failing
## to index. Truncating matches the runtime, which reads `anchors[0]` and
## `anchors[1]` and ignores the rest.
static func _pad_cells(value, count: int) -> Array:
	var out: Array = []
	if value is Array:
		for entry in value:
			if entry is Vector2i:
				out.append(entry)
			elif entry is Array and (entry as Array).size() >= 2:
				out.append(Vector2i(int(entry[0]), int(entry[1])))
			elif entry is Dictionary:
				out.append(Vector2i(int((entry as Dictionary).get("x", -1)),
					int((entry as Dictionary).get("y", -1))))
	if count > 0:
		while out.size() < count:
			out.append(UNSET)
		out.resize(count)
	return out


static func _zero_of(kind: String):
	match kind:
		INT: return 0
		FLOAT: return 0.0
		BOOL: return false
		CELLS: return []
		_: return ""


static func _is_number(value) -> bool:
	return value is int or value is float


static func _in_bounds(cell: Vector2i, size: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


## Two cells the same, ignoring the unchosen ones — two UNSET slots are not a
## duplicate, they are two things you have not done yet.
static func _has_duplicate(cells: Array) -> bool:
	var seen: Dictionary = {}
	for cell in cells:
		if cell == UNSET:
			continue
		if seen.has(cell):
			return true
		seen[cell] = true
	return false


## Value equality that works for the Arrays `cells` produces, where `==` on two
## separately-built Arrays of Vector2i is fine but `is_equal_approx` is not
## available and floats want an epsilon.
static func _same(a, b) -> bool:
	if a is float or b is float:
		return absf(float(a) - float(b)) < GeometryCore.EPSILON
	return a == b
