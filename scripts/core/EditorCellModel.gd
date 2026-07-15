class_name EditorCellModel extends RefCounted

## EditorCellModel
##
## Pure helpers for writing tiles into a LevelData.cell_data dictionary, correctly
## handling the two value shapes: a bare int for a plain tile, or a
## {"type": N, ...params} dict for a behavioral tile (currently TRIGGER_FOLD, which
## carries a channel + anchor pair). The editor previously wrote int-only, so a loaded
## trigger tile lost its params on any repaint (the "flatten" bug). Keeping this logic
## pure makes it unit-testable without the editor scene.

## Types that require a per-instance data dict rather than a bare int.
static func is_dict_type(type: int) -> bool:
	return type == TileTypes.TRIGGER_FOLD


## Default per-instance dict for a behavioral type (params the inspector then edits).
static func default_data(type: int) -> Dictionary:
	match type:
		TileTypes.TRIGGER_FOLD:
			return {"type": type, "channel": "A", "anchors": []}
		_:
			return {"type": type}


## Paint `type` at `pos`. EMPTY erases the entry; dict-types write/preserve a data dict
## (repainting the same dict-type keeps existing params — no flatten); everything else
## writes a bare int. Mutates and returns `cell_data`.
static func set_type(cell_data: Dictionary, pos: Vector2i, type: int) -> Dictionary:
	if type == TileTypes.EMPTY:
		cell_data.erase(pos)
		return cell_data

	if is_dict_type(type):
		var existing = cell_data.get(pos, null)
		# Preserve an existing well-formed dict of the SAME type (don't clobber params).
		if existing is Dictionary and int(existing.get("type", -1)) == type:
			return cell_data
		cell_data[pos] = default_data(type)
		return cell_data

	cell_data[pos] = type
	return cell_data


## Update the per-instance params of a dict-type tile already at `pos`. No-op if the
## cell isn't a dict-type. Only known keys are written; `type` is preserved.
static func set_trigger_params(cell_data: Dictionary, pos: Vector2i, channel: String, anchors: Array) -> Dictionary:
	var existing = cell_data.get(pos, null)
	if not (existing is Dictionary) or not is_dict_type(int(existing.get("type", -1))):
		return cell_data
	existing["channel"] = channel
	existing["anchors"] = anchors.duplicate(true)
	cell_data[pos] = existing
	return cell_data
